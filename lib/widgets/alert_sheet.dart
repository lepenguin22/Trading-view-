import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/alerts.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Bottom sheet for creating a price alert on one symbol.
class AlertSheet extends StatefulWidget {
  const AlertSheet({
    super.key,
    required this.symbol,
    required this.currency,
    this.currentPrice,
  });

  final String symbol;
  final String currency;

  /// The latest known price, used to seed the field and to warn when the
  /// condition is already true.
  final double? currentPrice;

  /// Opens the sheet. Resolves once it closes.
  static Future<void> show(
    BuildContext context, {
    required String symbol,
    required String currency,
    double? currentPrice,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => AlertSheet(
        symbol: symbol,
        currency: currency,
        currentPrice: currentPrice,
      ),
    );
  }

  @override
  State<AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends State<AlertSheet> {
  late final TextEditingController _controller;
  AlertDirection _direction = AlertDirection.above;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentPrice?.toStringAsFixed(2) ?? '',
    );
    _controller.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _threshold => double.tryParse(_controller.text.trim());

  /// True when the price already satisfies the condition being set up, which
  /// means the alert would fire on the very next check.
  bool get _alreadyMet {
    final price = widget.currentPrice;
    final threshold = _threshold;
    if (price == null || threshold == null) return false;
    return switch (_direction) {
      AlertDirection.above => price >= threshold,
      AlertDirection.below => price <= threshold,
    };
  }

  Future<void> _save() async {
    final threshold = _threshold;
    if (threshold == null) {
      setState(() => _error = 'Enter a price, for example 195.50.');
      return;
    }

    setState(() => _saving = true);
    final failure = await context.read<AlertsModel>().add(
      symbol: widget.symbol,
      direction: _direction,
      threshold: threshold,
      currency: widget.currency,
    );
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _saving = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      // Lifts the sheet clear of the keyboard.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Alert me when ${widget.symbol}',
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<AlertDirection>(
            segments: [
              for (final d in AlertDirection.values)
                ButtonSegment(
                  value: d,
                  label: Text(d.label),
                  icon: Icon(
                    d == AlertDirection.above
                        ? Icons.trending_up
                        : Icons.trending_down,
                  ),
                ),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: tabularFigures.copyWith(color: c.text, fontSize: 20),
            decoration: InputDecoration(
              labelText: 'Price',
              labelStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          if (widget.currentPrice != null) ...[
            const SizedBox(height: 8),
            Text(
              'Now ${formatPrice(widget.currentPrice!, widget.currency)}',
              style: TextStyle(color: c.textFaint, fontSize: 13),
            ),
          ],
          if (_alreadyMet) ...[
            const SizedBox(height: 8),
            Text(
              '${widget.symbol} already meets this condition, so the alert '
              'will fire on the next check.',
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create alert'),
            ),
          ),
        ],
      ),
    );
  }
}
