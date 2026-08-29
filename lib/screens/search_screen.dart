import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/yahoo.dart';
import '../models/types.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart';

/// Wait this long after the last keystroke before querying.
const _debounce = Duration(milliseconds: 350);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = YahooApi();
  final _controller = TextEditingController();

  Timer? _debounceTimer;

  // Cancels the previous request so out-of-order responses cannot overwrite
  // results for a query the user has already moved past.
  CancelToken? _inFlight;

  List<SearchResult> _results = const [];
  bool _searching = false;
  String? _error;
  String? _adding;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _inFlight?.cancel();
    _controller.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();

    if (_controller.text.trim().isEmpty) {
      _inFlight?.cancel();
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }

    _debounceTimer = Timer(_debounce, _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    _inFlight?.cancel();
    final token = CancelToken();
    _inFlight = token;

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final found = await _api.searchSymbols(query, token: token);
      if (token.isCancelled || !mounted) return;
      setState(() => _results = found);
    } catch (err) {
      if (token.isCancelled || !mounted) return;
      setState(() {
        _results = const [];
        _error = describeError(err);
      });
    } finally {
      if (!token.isCancelled && mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _add(String symbol) async {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() => _adding = symbol);

    final failure = await context.read<WatchlistModel>().addSymbol(symbol);
    if (!mounted) return;

    setState(() => _adding = null);
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = failure);
    }
  }

  String get _hint {
    if (_searching) return '';
    if (_controller.text.trim().isEmpty) {
      return 'Search for a listed company, fund or index — '
          'for example Apple, VOD.L or ^FTSE.';
    }
    return _error == null ? 'No matching symbols.' : '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<WatchlistModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Add symbol')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: TextStyle(color: c.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Company name or ticker',
                hintStyle: TextStyle(color: c.textFaint),
                filled: true,
                fillColor: c.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.accent),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: c.danger, fontSize: 13),
                  ),
                ),
              ),
            ),
          if (_searching)
            LinearProgressIndicator(color: c.accent, minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? _Hint(text: _hint)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return _ResultTile(
                        result: item,
                        alreadyAdded: model.has(item.symbol),
                        busy: _adding == item.symbol,
                        onAdd: () => _add(item.symbol),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.alreadyAdded,
    required this.busy,
    required this.onAdd,
  });

  final SearchResult result;
  final bool alreadyAdded;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      result.exchange,
      result.type,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Opacity(
      opacity: alreadyAdded ? 0.55 : 1,
      child: Semantics(
        button: true,
        enabled: !alreadyAdded && !busy,
        label:
            '${result.symbol}, ${result.name}'
            '${alreadyAdded ? ', already on your watchlist' : ''}',
        excludeSemantics: true,
        child: Material(
          color: c.card,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: alreadyAdded || busy ? null : onAdd,
            borderRadius: BorderRadius.circular(13),
            highlightColor: c.cardPressed,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.border),
              ),
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          result.symbol,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          result.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textMuted, fontSize: 14),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textFaint, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (busy)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.textMuted,
                      ),
                    )
                  else
                    Text(
                      alreadyAdded ? 'Added' : 'Add',
                      style: TextStyle(
                        color: alreadyAdded ? c.textFaint : c.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.colors.textMuted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }
}
