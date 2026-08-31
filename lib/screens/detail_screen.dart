import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/yahoo.dart';
import '../models/alert.dart';
import '../models/types.dart';
import '../models/valuation.dart';
import '../state/alerts.dart';
import '../state/valuation_store.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart';
import '../utils/chart.dart';
import '../utils/format.dart';
import '../utils/indicators.dart';
import '../widgets/alert_sheet.dart';
import '../widgets/change_pill.dart';
import '../widgets/price_chart.dart';
import '../widgets/rsi_pane.dart';
import 'settings_screen.dart';

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

  History? _history;
  bool _loading = true;
  String? _error;
  Candle? _scrubbed;
  ChartStyle _style = ChartStyle.candles;

  /// Days on screen. Zooming changes this; one candle is always one day.
  static const _defaultBars = 90;
  ChartWindow _window = const ChartWindow(start: 0, count: _defaultBars);

  /// True while a pinch, pan or scrub owns the chart, so the page underneath
  /// stops scrolling and the gesture is not stolen mid-move.
  bool _interacting = false;

  /// Indicators for the loaded range, recomputed only when the series changes
  /// rather than on every layout pass.
  Map<int, List<double?>> _mas = const {};
  List<double?> _rsi = const [];

  /// Which moving averages are drawn. All on by default; a period with no
  /// data for the range is shown greyed rather than hidden, so it is obvious
  /// the range is too short rather than the line silently missing.
  final Set<int> _visibleMas = {...maPeriods};

  CancelToken? _inFlight;

  @override
  void initState() {
    super.initState();
    _load();
    // Lazy and cached: opening a stock is the only thing that spends a
    // valuation request, and only when the cached copy has expired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ValuationModel>().ensureLoaded(widget.symbol);
    });
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
      final result = await _api.fetchHistory(widget.symbol, token: token);
      if (token.isCancelled || !mounted) return;
      // Computed once per load rather than per layout pass: a 200 SMA over a
      // few hundred bars is cheap, but the chart relays out on every scrub.
      final closes = result.closes;
      setState(() {
        _history = result;
        _mas = {
          for (final period in maPeriods)
            period: simpleMovingAverage(closes, period),
        };
        _rsi = relativeStrengthIndex(closes, rsiPeriod);
        // Open on the most recent bars; the clamp in the chart trims this to
        // whatever the screen can actually hold.
        _window = ChartWindow(
          start: (result.candles.length - _defaultBars).clamp(
            0,
            result.candles.length,
          ),
          count: _defaultBars,
        );
      });
    } catch (err) {
      if (token.isCancelled || !mounted) return;
      setState(() {
        _history = null;
        _mas = const {};
        _rsi = const [];
        _error = describeError(err);
      });
    } finally {
      if (!token.isCancelled && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Most bars the chart can show at this width. The chart clamps to this
  /// itself when it lays out; this mirror keeps the zoom buttons and the day
  /// count in step without plumbing the width back up.
  int get _maxBarsOnScreen =>
      maxCandlesFor(MediaQuery.of(context).size.width - 32);

  /// Width the price chart reserves for its axis, mirrored so the RSI pane
  /// below shares the same x-axis. Recomputed from the visible bars so it
  /// tracks the labels the chart is actually drawing.
  double get _axisGutter {
    final visible = _visible;
    if (visible.isEmpty) return 0;
    var min = visible.first.low;
    var max = visible.first.high;
    for (final candle in visible) {
      if (candle.low < min) min = candle.low;
      if (candle.high > max) max = candle.high;
    }
    final currency = _history?.currency ?? 'USD';
    return priceAxisWidth([
      for (final tick in priceTicksFor(min, max, currency)) tick.label,
    ]);
  }

  /// The bars currently on screen, or empty before history lands.
  List<Candle> get _visible {
    final history = _history;
    if (history == null) return const [];
    final w = _window.clampTo(
      total: history.candles.length,
      maxBars: _maxBarsOnScreen,
    );
    if (w.count <= 0) return const [];
    return history.candles.sublist(w.start, w.end);
  }

  /// While scrubbing, the header reports the bar under the finger; otherwise
  /// it reports the move across the visible window, so zooming changes what
  /// the percentage is measured over.
  _Headline? _buildHeadline() {
    final visible = _visible;
    if (visible.isEmpty) return null;

    final baseline = visible.first.open;

    final scrubbed = _scrubbed;
    if (scrubbed != null) {
      final change = scrubbed.close - baseline;
      return _Headline(
        price: scrubbed.close,
        change: change,
        changePercent: baseline != 0 ? (change / baseline) * 100 : 0,
        caption: formatPointDate(scrubbed.t, false),
        candle: scrubbed,
      );
    }

    final last = visible.last.close;
    final change = last - baseline;
    return _Headline(
      price: last,
      change: change,
      changePercent: baseline != 0 ? (change / baseline) * 100 : 0,
      caption:
          '${visible.length} days · '
          '${formatPointDate(visible.first.t, false)} – '
          '${formatPointDate(visible.last.t, false)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<WatchlistModel>();

    final quote = model.quotes[widget.symbol];
    final onWatchlist = model.has(widget.symbol);
    final headline = _buildHeadline();
    final currency = _history?.currency ?? quote?.currency ?? 'USD';
    final color = c.trend(headline?.change ?? 0);

    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: SingleChildScrollView(
        // A vertical scroll must not fight the chart's horizontal scrub
        // gesture, so scrolling is suspended while a finger is on the chart.
        physics: _interacting
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
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
                Expanded(child: _zoomControls()),
                _styleToggle(),
              ],
            ),
            if (_history != null) ...[
              const SizedBox(height: 6),
              _maLegend(),
              const SizedBox(height: 14),
              RsiPane(values: _rsi, window: _window, gutter: _axisGutter),
            ],
            if (quote != null) ...[
              const SizedBox(height: 20),
              _Stats(currency: currency, quote: quote),
            ],
            const SizedBox(height: 20),
            _FairValue(
              symbol: widget.symbol,
              price: quote?.price ?? _visible.lastOrNull?.close,
              currency: currency,
            ),
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
          window: _window,
          currency: _history?.currency ?? 'USD',
          onWindowChanged: (w) => setState(() => _window = w),
          onInteractingChanged: (v) {
            if (v != _interacting) setState(() => _interacting = v);
          },
          overlays: [
            for (var i = 0; i < maPeriods.length; i++)
              if (_visibleMas.contains(maPeriods[i]) &&
                  _mas[maPeriods[i]] != null)
                MaOverlay(
                  period: maPeriods[i],
                  color: context.colors.ma[i],
                  values: _mas[maPeriods[i]]!,
                ),
          ],
          baseline: _visible.isEmpty ? null : _visible.first.open,
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

  /// Zoom buttons alongside the pinch gesture: a phone pinch is fiddly for
  /// fine adjustment, and this also gives the feature a discoverable, and
  /// keyboard- and screen-reader-reachable, control.
  Widget _zoomControls() {
    final c = context.colors;
    final total = _history?.candles.length ?? 0;
    final visible = _visible.length;

    void zoom(double factor) {
      setState(() {
        _window = _window
            .zoomed(factor)
            .clampTo(total: total, maxBars: _maxBarsOnScreen);
      });
    }

    return Row(
      children: [
        IconButton(
          onPressed: total == 0 || visible <= ChartWindow.minBars
              ? null
              : () => zoom(1.5),
          icon: const Icon(Icons.zoom_in),
          tooltip: 'Zoom in, fewer days',
          visualDensity: VisualDensity.compact,
          color: c.textMuted,
        ),
        IconButton(
          onPressed: total == 0 || visible >= total
              ? null
              : () => zoom(1 / 1.5),
          icon: const Icon(Icons.zoom_out),
          tooltip: 'Zoom out, more days',
          visualDensity: VisualDensity.compact,
          color: c.textMuted,
        ),
        if (visible > 0)
          Text(
            '$visible days',
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
      ],
    );
  }

  /// Legend for the moving averages. Always present — three lines of the same
  /// mark type must not be identified by colour alone — and each chip toggles
  /// its line.
  Widget _maLegend() {
    final c = context.colors;
    final currency = _history?.currency ?? 'USD';

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < maPeriods.length; i++)
          Builder(
            builder: (context) {
              final period = maPeriods[i];
              final series = _mas[period];
              final latest = series?.lastWhere(
                (v) => v != null,
                orElse: () => null,
              );
              // No value at all means the range holds fewer bars than the
              // period; the chip stays visible but reads as unavailable.
              final available = latest != null;
              final shown = _visibleMas.contains(period) && available;

              return InkWell(
                onTap: available
                    ? () => setState(() {
                        if (!_visibleMas.remove(period)) {
                          _visibleMas.add(period);
                        }
                      })
                    : null,
                borderRadius: BorderRadius.circular(7),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: shown ? c.ma[i] : c.textFaint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // Identity is the swatch; the text stays in ink so a
                      // value never has to be read off a coloured label.
                      Text(
                        'MA$period',
                        style: TextStyle(
                          color: shown ? c.textMuted : c.textFaint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        available ? formatPrice(latest, currency) : 'n/a',
                        style: tabularFigures.copyWith(
                          color: shown ? c.text : c.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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

/// Price against a discounted-cash-flow fair value.
///
/// Always shown beside the live price rather than in place of it: the DCF is a
/// third party's projection, and the section names its source and its age so
/// it is read as an opinion rather than a measurement.
class _FairValue extends StatelessWidget {
  const _FairValue({
    required this.symbol,
    required this.price,
    required this.currency,
  });

  final String symbol;
  final double? price;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<ValuationModel>();

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Fair value (DCF)',
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (model.isLoading(symbol))
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _body(context, model),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ValuationModel model) {
    final c = context.colors;

    if (!model.hasApiKey) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a Financial Modeling Prep API key to see a fair value '
            'estimate. Their free tier is enough.',
            style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Open settings'),
          ),
        ],
      );
    }

    final error = model.errorFor(symbol);
    if (error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: () => model.ensureLoaded(symbol, force: true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final valuation = model.valuationFor(symbol);
    if (valuation == null) {
      return Text(
        model.isLoading(symbol) ? 'Fetching…' : 'No valuation yet.',
        style: TextStyle(color: c.textMuted, fontSize: 13),
      );
    }

    final live = price;
    final verdict = live == null ? null : verdictFor(live, valuation.dcf);
    final margin = live == null ? null : marginOfSafety(live, valuation.dcf);
    // Green for a discount, red for a premium — the same direction the rest of
    // the app uses for "good for the holder".
    final tint = verdict == null
        ? c.textMuted
        : verdict.isCheap
        ? c.up
        : verdict.isExpensive
        ? c.down
        : c.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatPrice(valuation.dcf, currency),
              style: tabularFigures.copyWith(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            if (verdict != null)
              Expanded(
                child: Text(
                  verdict.label,
                  style: TextStyle(
                    color: tint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (margin != null) ...[
          const SizedBox(height: 6),
          Text(
            margin >= 0
                ? '${margin.toStringAsFixed(1)}% below fair value'
                : '${margin.abs().toStringAsFixed(1)}% above fair value',
            style: tabularFigures.copyWith(color: tint, fontSize: 13),
          ),
        ],
        if (valuation.currency != currency) ...[
          const SizedBox(height: 8),
          // Comparing a USD model output against a pence-quoted price would be
          // nonsense, so the mismatch is stated rather than hidden.
          Text(
            'Quoted in ${valuation.currency} while the price is in $currency — '
            'these are not directly comparable.',
            style: TextStyle(color: c.danger, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Financial Modeling Prep · ${formatUpdatedAt(valuation.fetchedAt).replaceFirst("Updated ", "fetched ")}'
          '${isStale(valuation) ? " · refreshing soon" : ""}',
          style: TextStyle(color: c.textFaint, fontSize: 11.5),
        ),
      ],
    );
  }
}
