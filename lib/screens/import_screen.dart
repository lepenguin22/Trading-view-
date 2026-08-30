import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/portfolio_source.dart';
import '../api/yahoo.dart' show describeError;
import '../state/storage.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart';

/// Imports a watchlist from a spreadsheet published as CSV.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.source, this.storage});

  /// Injected in tests; both reach the network or the platform otherwise.
  final PortfolioSource? source;
  final WatchlistStorage? storage;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final PortfolioSource _source = widget.source ?? PortfolioSource();
  late final WatchlistStorage _storage = widget.storage ?? WatchlistStorage();
  final _controller = TextEditingController();

  bool _busy = false;
  String? _error;
  ImportOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _restoreUrl();
  }

  Future<void> _restoreUrl() async {
    final saved = await _storage.loadSheetUrl();
    if (saved != null && mounted && _controller.text.isEmpty) {
      _controller.text = saved;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // Only close a client this screen created.
    if (widget.source == null) _source.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    FocusScope.of(context).unfocus();
    final url = _controller.text.trim();

    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
    });

    try {
      final symbols = await _source.fetchSymbols(url);
      if (!mounted) return;

      final outcome = await context.read<WatchlistModel>().importSymbols(
        symbols,
      );
      if (!mounted) return;

      // Remembered only after a fetch that worked, so a bad URL is not the one
      // that comes back next time.
      await _storage.saveSheetUrl(url);
      if (!mounted) return;
      setState(() => _outcome = outcome);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = describeError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Import portfolio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Paste the link to a spreadsheet published as CSV. Every ticker in '
            'its first holdings table is checked against the price feed and '
            'added to your watchlist.',
            style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_busy,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Published CSV link',
              labelStyle: TextStyle(color: c.textMuted),
              hintText: 'https://docs.google.com/…/pub?output=csv',
              hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
              filled: true,
              fillColor: c.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
            ),
            onSubmitted: (_) => _busy ? null : _import(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _import,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Import'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: c.danger, fontSize: 14, height: 1.4),
              ),
            ),
          ],
          if (_outcome != null) ...[
            const SizedBox(height: 18),
            _Result(outcome: _outcome!),
          ],
          const SizedBox(height: 28),
          _Instructions(),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.outcome});

  final ImportOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              outcome.added.isEmpty
                  ? 'Nothing new to add'
                  : 'Added ${outcome.added.length} '
                        '${outcome.added.length == 1 ? "symbol" : "symbols"}',
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (outcome.added.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              outcome.added.join(', '),
              style: TextStyle(color: c.up, fontSize: 13, height: 1.4),
            ),
          ],
          if (outcome.alreadyPresent.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${outcome.alreadyPresent.length} already on your watchlist',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
          ],
          if (outcome.failed.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Not added',
              style: TextStyle(
                color: c.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            // Named individually rather than counted: these are usually typos
            // in the sheet, and the user needs to know which cell to fix.
            for (final entry in outcome.failed.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${entry.key} — ${entry.value}',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Instructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Publishing a Google Sheet',
          style: TextStyle(
            color: c.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final step in const [
          'In Sheets, choose File → Share → Publish to web.',
          'Select the single tab holding your positions — not "Entire document".',
          'Choose Comma-separated values (.csv) and publish.',
          'Copy the link it gives you and paste it above.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '•  $step',
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(12),
          child: Text(
            'Publishing makes that tab readable by anyone who has the link. '
            'Publish only the tab with your positions, and keep tabs holding '
            'balances or salary out of it.',
            style: TextStyle(color: c.textMuted, fontSize: 12.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Only the first table with a "Ticker" or "Symbol" column is read, and '
          'it stops at the first blank row — so a table of closed positions '
          'further down the same tab is left alone.',
          style: TextStyle(color: c.textFaint, fontSize: 12.5, height: 1.45),
        ),
      ],
    );
  }
}
