/// A single point on a price series.
class PricePoint {
  const PricePoint({required this.t, required this.c});

  /// Epoch seconds, as returned by the upstream feed.
  final int t;

  /// Close price for the interval.
  final double c;

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
    t: (json['t'] as num).toInt(),
    c: (json['c'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {'t': t, 'c': c};

  @override
  bool operator ==(Object other) =>
      other is PricePoint && other.t == t && other.c == c;

  @override
  int get hashCode => Object.hash(t, c);

  @override
  String toString() => 'PricePoint($t, $c)';
}

/// One OHLC bar: the open, high, low and close over a single interval.
///
/// Separate from [PricePoint], which stays a bare close for the watchlist
/// sparkline. Only the detail chart needs the full bar, and [Quote.spark] is
/// persisted, so widening that type would need a cache migration for no gain.
class Candle {
  const Candle({
    required this.t,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  /// Epoch seconds at the start of the interval.
  final int t;
  final double open;
  final double high;
  final double low;
  final double close;

  /// True when the bar closed at or above where it opened. A doji (open ==
  /// close) is drawn as up, matching the convention in most trading apps.
  bool get isUp => close >= open;

  @override
  bool operator ==(Object other) =>
      other is Candle &&
      other.t == t &&
      other.open == open &&
      other.high == high &&
      other.low == low &&
      other.close == close;

  @override
  int get hashCode => Object.hash(t, open, high, low, close);

  @override
  String toString() => 'Candle($t, o:$open h:$high l:$low c:$close)';
}

/// Everything the UI needs to render one row of the watchlist.
class Quote {
  const Quote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.previousClose,
    required this.change,
    required this.changePercent,
    required this.currency,
    required this.exchange,
    required this.marketState,
    required this.dayHigh,
    required this.dayLow,
    required this.spark,
    required this.fetchedAt,
  });

  final String symbol;

  /// Human readable name, e.g. "Apple Inc.". Falls back to the symbol.
  final String name;
  final double price;

  /// Previous close, used as the baseline for the day's change.
  final double previousClose;
  final double change;
  final double changePercent;
  final String currency;

  /// Exchange short name, e.g. "NMS", "LSE".
  final String exchange;

  /// "REGULAR" | "PRE" | "POST" | "CLOSED" | "".
  final String marketState;
  final double? dayHigh;
  final double? dayLow;

  /// Intraday series for the row's sparkline. May be empty.
  final List<PricePoint> spark;

  /// When this quote was fetched (epoch ms).
  final int fetchedAt;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    symbol: json['symbol'] as String,
    name: json['name'] as String? ?? json['symbol'] as String,
    price: (json['price'] as num).toDouble(),
    previousClose: (json['previousClose'] as num).toDouble(),
    change: (json['change'] as num).toDouble(),
    changePercent: (json['changePercent'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'USD',
    exchange: json['exchange'] as String? ?? '',
    marketState: json['marketState'] as String? ?? '',
    dayHigh: (json['dayHigh'] as num?)?.toDouble(),
    dayLow: (json['dayLow'] as num?)?.toDouble(),
    spark: (json['spark'] as List<dynamic>? ?? const [])
        .map((e) => PricePoint.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    fetchedAt: (json['fetchedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'price': price,
    'previousClose': previousClose,
    'change': change,
    'changePercent': changePercent,
    'currency': currency,
    'exchange': exchange,
    'marketState': marketState,
    'dayHigh': dayHigh,
    'dayLow': dayLow,
    'spark': spark.map((p) => p.toJson()).toList(growable: false),
    'fetchedAt': fetchedAt,
  };
}

/// Daily price history for the detail screen chart.
///
/// One candle is one trading day, always. The visible span is chosen by
/// zooming rather than by picking a range, so this carries the whole fetched
/// series and the UI decides what slice to draw.
class History {
  const History({
    required this.symbol,
    required this.candles,
    required this.currency,
  });

  final String symbol;

  /// Daily OHLC bars, oldest first.
  final List<Candle> candles;
  final String currency;

  /// Closing prices, for the line view and the indicators.
  List<double> get closes => [for (final c in candles) c.close];
}

/// A symbol search hit.
class SearchResult {
  const SearchResult({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.type,
  });

  final String symbol;
  final String name;
  final String exchange;

  /// e.g. "EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY".
  final String type;
}

/// The slice of a daily series currently on screen.
///
/// Pure and clamped, so the zoom and pan gestures cannot walk the view off the
/// end of the data or collapse it to nothing.
class ChartWindow {
  const ChartWindow({required this.start, required this.count});

  /// Index of the leftmost visible bar.
  final int start;

  /// How many bars are visible.
  final int count;

  int get end => start + count;

  /// Fewest bars the chart will show, so zooming in cannot leave one candle
  /// filling the screen.
  static const minBars = 12;

  /// Clamps this window to a series of [total] bars, showing at most
  /// [maxBars]. The count settles first, then the start, so a window that has
  /// been panned past the end slides back rather than shrinking.
  ChartWindow clampTo({required int total, required int maxBars}) {
    if (total <= 0) return const ChartWindow(start: 0, count: 0);

    final upper = maxBars < minBars ? minBars : maxBars;
    var nextCount = count.clamp(minBars, upper);
    if (nextCount > total) nextCount = total;

    final nextStart = start.clamp(0, total - nextCount);
    return ChartWindow(start: nextStart, count: nextCount);
  }

  /// Zooms by [factor] (>1 zooms in) about [focal], a 0..1 position across the
  /// visible width. Anchoring on the focal point is what makes a pinch feel
  /// like it is scaling the chart under the fingers rather than the left edge.
  ChartWindow zoomed(double factor, {double focal = 0.5}) {
    if (!factor.isFinite || factor <= 0) return this;

    final nextCount = (count / factor).round().clamp(1, 1 << 30);
    // The bar under the focal point stays under it.
    final anchor = start + focal * count;
    final nextStart = (anchor - focal * nextCount).round();
    return ChartWindow(start: nextStart, count: nextCount);
  }

  /// Slides the window by [bars]; positive moves toward newer data.
  ChartWindow panned(int bars) =>
      ChartWindow(start: start + bars, count: count);

  @override
  bool operator ==(Object other) =>
      other is ChartWindow && other.start == start && other.count == count;

  @override
  int get hashCode => Object.hash(start, count);

  @override
  String toString() => 'ChartWindow($start, $count)';
}
