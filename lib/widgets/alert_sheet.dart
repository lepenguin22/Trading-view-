import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/crossover.dart';
import '../state/alerts.dart';
import '../utils/indicators.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// One selectable crossover condition: a spec paired with a direction.
typedef _CrossChoice = ({CrossoverSpec spec, CrossDirection direction});

/// Every crossover the sheet offers, as concrete named conditions.
///
/// Flattened rather than asking for a crossover and a direction separately:
/// "Golden Cross" is one thing the user wants, not two choices they have to
/// combine correctly.
final _crossChoices = <_CrossChoice>[
  for (final spec in crossoverSpecs)
    for (final direction in CrossDirection.values)
      (spec: spec, direction: direction),
];

/// Bottom sheet for creating an alert on one symbol.
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
  AlertKind _kind = AlertKind.price;
  AlertDirection _direction = AlertDirection.above;
  _CrossChoice _cross = _crossChoices.first;
  String? _error;
  bool _saving = false;

  /// Switches the numeric field to what the new kind measures.
  ///
  /// The seed is replaced rather than kept: a price of 195.50 is a nonsensical
  /// RSI level, and leaving it there invites a mistake.
  void _selectKind(AlertKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _error = null;
      _controller.text = switch (kind) {
        AlertKind.price => widget.currentPrice?.toStringAsFixed(2) ?? '',
        AlertKind.rsi =>
          _direction == AlertDirection.above
              ? rsiOverbought.toStringAsFixed(0)
              : rsiOversold.toStringAsFixed(0),
        AlertKind.crossover => '',
      };
    });
  }

  void _selectDirection(AlertDirection direction) {
    setState(() {
      _direction = direction;
      // The RSI defaults follow the side being watched: above means
      // overbought, below means oversold.
      if (_kind == AlertKind.rsi) {
        _controller.text = direction == AlertDirection.above
            ? rsiOverbought.toStringAsFixed(0)
            : rsiOversold.toStringAsFixed(0);
      }
    });
  }

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
  ///
  /// Only meaningful for a price alert. An RSI level cannot be checked from a
  /// quote, and a crossover is an event rather than a level, so neither can be
  /// "already met".
  bool get _alreadyMet {
    if (_kind != AlertKind.price) return false;
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
    if (_kind != AlertKind.crossover && threshold == null) {
      setState(
        () => _error = _kind == AlertKind.rsi
            ? 'Enter an RSI level, for example 30.'
            : 'Enter a price, for example 195.50.',
      );
      return;
    }

    setState(() => _saving = true);
    final failure = await context.read<AlertsModel>().add(
      symbol: widget.symbol,
      kind: _kind,
      crossoverId: _kind == AlertKind.crossover ? _cross.spec.id : null,
      direction: _kind == AlertKind.crossover
          ? (_cross.direction == CrossDirection.up
                ? AlertDirection.above
                : AlertDirection.below)
          : _direction,
      threshold: threshold ?? 0,
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
          SegmentedButton<AlertKind>(
            segments: const [
              ButtonSegment(value: AlertKind.price, label: Text('Price')),
              ButtonSegment(value: AlertKind.rsi, label: Text('RSI')),
              ButtonSegment(
                value: AlertKind.crossover,
                label: Text('Crossover'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => _selectKind(s.first),
          ),
          if (_kind == AlertKind.crossover) ...[
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: '${_cross.spec.id}.${_cross.direction.name}',
              onChanged: (value) => setState(() {
                _cross = _crossChoices.firstWhere(
                  (ch) => '${ch.spec.id}.${ch.direction.name}' == value,
                  orElse: () => _cross,
                );
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in _crossChoices)
                    RadioListTile<String>(
                      value: '${choice.spec.id}.${choice.direction.name}',
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: c.accent,
                      title: Text(
                        choice.spec.labelFor(choice.direction),
                        style: TextStyle(color: c.text, fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Checked once a day\'s bar has closed, so this arrives with the '
              'next background check rather than the moment it happens. Only '
              'crossings from now on count — an old one will not fire it.',
              style: TextStyle(color: c.textFaint, fontSize: 12.5, height: 1.4),
            ),
          ] else ...[
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
              onSelectionChanged: (s) => _selectDirection(s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: tabularFigures.copyWith(color: c.text, fontSize: 20),
              decoration: InputDecoration(
                labelText: _kind == AlertKind.rsi ? 'RSI level' : 'Price',
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
            if (_kind == AlertKind.price && widget.currentPrice != null) ...[
              const SizedBox(height: 8),
              Text(
                'Now ${formatPrice(widget.currentPrice!, widget.currency)}',
                style: TextStyle(color: c.textFaint, fontSize: 13),
              ),
            ],
            if (_kind == AlertKind.rsi) ...[
              const SizedBox(height: 8),
              Text(
                'Below ${rsiOversold.toStringAsFixed(0)} is the usual '
                'oversold mark, above ${rsiOverbought.toStringAsFixed(0)} '
                'overbought. Read from daily closes on the next background '
                'check.',
                style: TextStyle(
                  color: c.textFaint,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
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
