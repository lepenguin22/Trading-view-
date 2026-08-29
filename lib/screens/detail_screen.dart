import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/yahoo.dart';
import '../models/alert.dart';
import '../models/types.dart';
import '../state/alerts.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/alert_sheet.dart';
import '../widgets/change_pill.dart';
import '../widgets/price_chart.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  /// Shared with the rest of the app, so this screen neither creates nor
  /// closes it.
  late final YahooApi _api = context.read<YahooApi>();

  RangeKey _range = RangeKey.d1;
  History? _history;
  bool _loading = true;
  String? _error;
  Candle? _scrubbed;
  ChartStyle _style = ChartStyle.candles;

  CancelToken? _inFlight;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inFlight?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _inFlight?.cancel();
    final token = CancelToken();
    _inFlight = token;

    setState(() {
      _loading = true;
      _error = null;
      _scrubbed = null;
    });

    try {
      final result = await _api.fetchHistory(
        widget.symbol,
        _range,
        token: token,
      );
      if (token.isCancelled || !mounted) return;
      setState(() => _history = result);
    } catch (err) {
      if (token.isCancelled || !mounted) return;
      setState(() {
        _history = null;
        _error = describeError(err);
      });
    } finally {
      if (!token.isCancelled && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectRange(RangeKey next) {
    if (next == _range) return;
    HapticFeedback.selectionClick();
    setState(() => _range = next);
    _load();
  }

  /// While scrubbing, the header reports the point under the finger; otherwise
  /// it reports the latest price for the selected range.
  _Headline? _buildHeadline(Quote? quote) {
    final history = _history;
    if (history == null) return null;

    final scrubbed = _scrubbed;
    if (scrubbed != null) {
      final change = scrubbed.close - history.first;
      return _Headline(
        price: scrubbed.close,
        change: change,
        changePercent: history.first != 0 ? (change / history.first) * 100 : 0,
        caption: formatPointDate(scrubbed.t, _range.intraday),
        candle: scrubbed,
      );
    }

    final String caption;
    if (_range == RangeKey.d1) {
      final state = describeMarketState(quote?.marketState ?? '');
      caption = state.isNotEmpty ? state : 'Today';
    } else {
      caption = 'Past ${_range.longLabel}';
    }

    return _Headline(
      price: history.last,
      change: history.change,
      changePercent: history.changePercent,
      caption: caption,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<WatchlistModel>();

    final quote = model.quotes[widget.symbol];
    final onWatchlist = model.has(widget.symbol);
    final headline = _buildHeadline(quote);
    final currency = _history?.currency ?? quote?.currency ?? 'USD';
    final color = c.trend(headline?.change ?? 0);

    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: SingleChildScrollView(
        // A vertical scroll must not fight the chart's horizontal scrub
        // gesture, so scrolling is suspended while a finger is on the chart.
        physics: _scrubbed == null
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              quote?.name ?? widget.symbol,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textMuted, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              headline != null ? formatPrice(headline.price, currency) : '—',
              style: tabularFigures.copyWith(
                color: c.text,
                fontSize: 36,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: headline == null
                  ? null
                  : Row(
                      children: [
                        Text(
                          formatChange(headline.change),
                          style: tabularFigures.copyWith(
                            color: color,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ChangePill(
                          changePercent: headline.changePercent,
                          large: true,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 18,
              child: headline?.candle != null
                  ? _OhlcStrip(candle: headline!.candle!, currency: currency)
                  : Text(
                      headline?.caption ?? '',
                      style: TextStyle(color: c.textFaint, fontSize: 13),
                    ),
            ),
            const SizedBox(height: 12),
            _chartArea(color),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _rangePicker(color)),
                _styleToggle(),
              ],
            ),
            if (quote != null) ...[
              const SizedBox(height: 20),
              _Stats(currency: currency, quote: quote),
            ],
            const SizedBox(height: 20),
            _alertsSection(currency, headline?.price ?? quote?.price),
            const SizedBox(height: 20),
            _watchButton(onWatchlist),
          ],
        ),
      ),
    );
  }

  Widget _chartArea(Color color) {
    final c = context.colors;
    final history = _history;

    if (_loading && history == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.danger, fontSize: 14),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.accent,
                  side: BorderSide(color: c.border),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (history == null) return const SizedBox(height: 220);

    return Stack(
      alignment: Alignment.center,
      children: [
        PriceChart(
          candles: history.candles,
          color: color,
          style: _style,
          baseline: history.first,
          onScrub: (candle) => setState(() => _scrubbed = candle),
        ),
        // Keep the old chart on screen while a new range loads.
        if (_loading) const IgnorePointer(child: CircularProgressIndicator()),
      ],
    );
  }

  /// Switches between candlesticks and the close-price line. Candles show the
  /// detail of each bar; the line is easier to read for the shape of a long
  /// range.
  Widget _styleToggle() {
    final c = context.colors;
    final next = _style == ChartStyle.candles
        ? ChartStyle.line
        : ChartStyle.candles;

    return TextButton.icon(
      onPressed: () => setState(() {
        _style = next;
        _scrubbed = null;
      }),
      icon: Icon(next.icon, size: 18),
      label: Text(next.label),
      style: TextButton.styleFrom(
        foregroundColor: c.textMuted,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _rangePicker(Color color) {
    final c = context.colors;

    return Row(
      children: [
        for (final r in RangeKey.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: r == _range,
                label: 'Show ${r.longLabel}',
                child: Material(
                  color: r == _range
                      ? color.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    onTap: () => _selectRange(r),
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        r.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: r == _range ? color : c.textMuted,
                          fontSize: 14,
                          fontWeight: r == _range
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _alertsSection(String currency, double? price) {
    final c = context.colors;
    final alerts = context.watch<AlertsModel>().forSymbol(widget.symbol);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Price alerts',
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton.icon(
              onPressed: () => AlertSheet.show(
                context,
                symbol: widget.symbol,
                currency: currency,
                currentPrice: price,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: TextButton.styleFrom(foregroundColor: c.accent),
            ),
          ],
        ),
        if (alerts.isEmpty)
          Text(
            'None yet. Add one to be notified when ${widget.symbol} crosses a '
            'price you choose.',
            style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
          )
        else
          for (final alert in alerts) _AlertRow(alert: alert),
      ],
    );
  }

  Widget _watchButton(bool onWatchlist) {
    final c = context.colors;
    final model = context.read<WatchlistModel>();

    return SizedBox(
      height: 50,
      child: onWatchlist
          ? OutlinedButton(
              onPressed: () => model.removeSymbol(widget.symbol),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textMuted,
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('Remove from watchlist'),
            )
          : FilledButton(
              onPressed: () async {
                // Resolved before the await so nothing reaches for a
                // BuildContext once the fetch has come back.
                final messenger = ScaffoldMessenger.of(context);
                final failure = await model.addSymbol(widget.symbol);
                if (failure != null && mounted) {
                  messenger.showSnackBar(SnackBar(content: Text(failure)));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('Add to watchlist'),
            ),
    );
  }
}

class _Headline {
  const _Headline({
    required this.price,
    required this.change,
    required this.changePercent,
    required this.caption,
    this.candle,
  });

  final double price;
  final double change;
  final double changePercent;
  final String caption;

  /// The bar under the finger while scrubbing, so its OHLC can be shown.
  final Candle? candle;
}

class _Stats extends StatelessWidget {
  const _Stats({required this.currency, required this.quote});

  final String currency;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <(String, String)>[
      ('Previous close', formatPrice(quote.previousClose, currency)),
      (
        'Day high',
        quote.dayHigh != null ? formatPrice(quote.dayHigh!, currency) : '—',
      ),
      (
        'Day low',
        quote.dayLow != null ? formatPrice(quote.dayLow!, currency) : '—',
      ),
      ('Exchange', quote.exchange.isNotEmpty ? quote.exchange : '—'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? Border(bottom: BorderSide(color: c.border))
                    : null,
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(color: c.textMuted, fontSize: 14),
                  ),
                  Text(
                    rows[i].$2,
                    style: tabularFigures.copyWith(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final PriceAlert alert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.read<AlertsModel>();
    final armed = alert.enabled && !alert.hasTriggered;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(
              alert.direction == AlertDirection.above
                  ? Icons.trending_up
                  : Icons.trending_down,
              size: 20,
              color: armed
                  ? (alert.direction == AlertDirection.above ? c.up : c.down)
                  : c.textFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${alert.direction.phrase} '
                '${formatPrice(alert.threshold, alert.currency)}'
                '${alert.hasTriggered ? ' · fired' : ''}',
                style: TextStyle(
                  color: armed ? c.text : c.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Switch(
              value: armed,
              activeThumbColor: c.accent,
              onChanged: (v) => model.setEnabled(alert.id, v),
            ),
            IconButton(
              onPressed: () => model.remove(alert.id),
              icon: Icon(Icons.close, size: 18, color: c.textFaint),
              tooltip: 'Delete alert',
            ),
          ],
        ),
      ),
    );
  }
}

/// Open / high / low / close for the bar under the finger.
class _OhlcStrip extends StatelessWidget {
  const _OhlcStrip({required this.candle, required this.currency});

  final Candle candle;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = candle.isUp ? c.up : c.down;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final (label, value) in [
            ('O', candle.open),
            ('H', candle.high),
            ('L', candle.low),
            ('C', candle.close),
          ]) ...[
            Text('$label ', style: TextStyle(color: c.textFaint, fontSize: 12)),
            Text(
              formatPrice(value, currency),
              style: tabularFigures.copyWith(color: color, fontSize: 12),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}
