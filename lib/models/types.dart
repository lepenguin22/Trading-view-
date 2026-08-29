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

/// Aggregates [candles] into at most [maxCount] bars.
///
/// A phone is only a few hundred pixels wide, so a 5Y weekly series drawn one
/// bar per point is an unreadable smear. Merging adjacent bars is the same
/// operation as moving to a coarser timeframe: the bucket opens where the
/// first bar opened, closes where the last one closed, and spans the extremes
/// in between.
List<Candle> aggregateCandles(List<Candle> candles, int maxCount) {
  if (maxCount <= 0) return const [];
  if (candles.length <= maxCount) return candles;

  // Round up so the bucket count never exceeds maxCount.
  final bucketSize = (candles.length + maxCount - 1) ~/ maxCount;

  final out = <Candle>[];
  for (var start = 0; start < candles.length; start += bucketSize) {
    final end = (start + bucketSize).clamp(0, candles.length);
    var high = candles[start].high;
    var low = candles[start].low;
    for (var i = start + 1; i < end; i++) {
      if (candles[i].high > high) high = candles[i].high;
      if (candles[i].low < low) low = candles[i].low;
    }
    out.add(
      Candle(
        t: candles[start].t,
        open: candles[start].open,
        high: high,
        low: low,
        close: candles[end - 1].close,
      ),
    );
  }
  return out;
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

/// A price history series for the detail screen chart.
class History {
  const History({
    required this.symbol,
    required this.range,
    required this.candles,
    required this.currency,
    required this.first,
    required this.last,
    required this.change,
    required this.changePercent,
  });

  final String symbol;
  final RangeKey range;

  /// Full OHLC bars. The line chart reads [closes] from these.
  final List<Candle> candles;
  final String currency;

  /// Closing prices, for the line view and any close-based geometry.
  List<double> get closes => [for (final c in candles) c.close];

  /// Baseline the range's change is measured against.
  final double first;
  final double last;
  final double change;
  final double changePercent;
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

/// The ranges offered on the detail screen, with the upstream range/interval
/// pair each one maps to. Intervals are chosen to keep every series in the low
/// hundreds of points, which is plenty for a phone-width chart.
enum RangeKey {
  d1('1D', '1d', '5m', 'day'),
  w1('1W', '5d', '30m', 'week'),
  m1('1M', '1mo', '1d', 'month'),
  m3('3M', '3mo', '1d', '3 months'),
  y1('1Y', '1y', '1d', 'year'),
  y5('5Y', '5y', '1wk', '5 years');

  const RangeKey(this.label, this.range, this.interval, this.longLabel);

  /// Button label, e.g. "1D".
  final String label;

  /// Upstream `range` parameter.
  final String range;

  /// Upstream `interval` parameter.
  final String interval;

  /// Prose form for captions and accessibility, e.g. "3 months".
  final String longLabel;

  /// True where points are finer than one a day, which changes how their
  /// timestamps are labelled.
  bool get intraday => this == RangeKey.d1 || this == RangeKey.w1;
}
