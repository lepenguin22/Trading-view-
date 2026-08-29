import '../models/types.dart';

/// Pure parsers for the Yahoo Finance JSON payloads.
///
/// These are deliberately kept free of any HTTP so they can be unit tested
/// against recorded fixtures. The upstream feed is undocumented and changes
/// shape occasionally, so every field is read defensively: a missing or
/// non-numeric field degrades the result rather than throwing.

/// Thrown when a payload is structurally unusable (no result, or upstream
/// error).
class FeedException implements Exception {
  const FeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

double? _num(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  return null;
}

String? _str(Object? v) {
  if (v is String && v.isNotEmpty) return v;
  return null;
}

Map<String, dynamic>? _map(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

List<dynamic> _list(Object? v) => v is List ? v : const [];

/// Pulls `chart.result[0]`, raising a [FeedException] if the payload carries an
/// error object instead.
Map<String, dynamic> _chartResult(Object? payload) {
  final root = _map(payload);
  final chart = root == null ? null : _map(root['chart']);
  if (chart == null) {
    throw const FeedException('Unexpected response: no chart object');
  }

  final err = _map(chart['error']);
  if (err != null) {
    throw FeedException(
      _str(err['description']) ?? _str(err['code']) ?? 'Upstream error',
    );
  }

  final results = _list(chart['result']);
  final first = results.isEmpty ? null : _map(results.first);
  if (first == null) {
    throw const FeedException('Unexpected response: no chart data');
  }
  return first;
}

/// Zips the parallel `timestamp` and `indicators.quote[0].close` arrays into
/// points, dropping entries where either side is null. Yahoo pads both arrays
/// with nulls for halted or not-yet-traded intervals.
List<PricePoint> parsePoints(Map<String, dynamic> result) {
  final timestamps = _list(result['timestamp']);
  final indicators = _map(result['indicators']) ?? const <String, dynamic>{};
  final quoteArr = _list(indicators['quote']);
  final quote0 = quoteArr.isEmpty
      ? null
      : _map(quoteArr.first) ?? const <String, dynamic>{};
  final closes = _list(quote0?['close']);

  final points = <PricePoint>[];
  final n = timestamps.length < closes.length
      ? timestamps.length
      : closes.length;
  for (var i = 0; i < n; i++) {
    final t = _num(timestamps[i]);
    final c = _num(closes[i]);
    if (t != null && c != null) {
      points.add(PricePoint(t: t.toInt(), c: c));
    }
  }
  return points;
}

/// Builds a watchlist quote from a `range=1d` chart payload.
Quote parseQuote(Object? payload, {int? fetchedAt}) {
  final result = _chartResult(payload);
  final meta = _map(result['meta']) ?? const <String, dynamic>{};
  final points = parsePoints(result);
  final lastPoint = points.isNotEmpty ? points.last.c : null;

  final symbol = _str(meta['symbol']);
  if (symbol == null) {
    throw const FeedException('Unexpected response: no symbol');
  }

  final price = _num(meta['regularMarketPrice']) ?? lastPoint;
  if (price == null) {
    throw FeedException('No price available for $symbol');
  }

  // previousClose is the prior session's close; chartPreviousClose is the close
  // before the requested range begins. For a 1d range they agree, but only the
  // former is present on every payload.
  final previousClose =
      _num(meta['previousClose']) ??
      _num(meta['chartPreviousClose']) ??
      (points.isNotEmpty ? points.first.c : price);

  final change = price - previousClose;

  return Quote(
    symbol: symbol,
    name: _str(meta['longName']) ?? _str(meta['shortName']) ?? symbol,
    price: price,
    previousClose: previousClose,
    change: change,
    // A zero previous close would only happen on a malformed payload; guard
    // anyway so the UI never renders NaN%.
    changePercent: previousClose != 0 ? (change / previousClose) * 100 : 0,
    currency: _str(meta['currency']) ?? 'USD',
    exchange:
        _str(meta['fullExchangeName']) ?? _str(meta['exchangeName']) ?? '',
    marketState: _str(meta['marketState']) ?? '',
    dayHigh: _num(meta['regularMarketDayHigh']),
    dayLow: _num(meta['regularMarketDayLow']),
    spark: points,
    fetchedAt: fetchedAt ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Builds a detail-screen series from a chart payload for the given range.
History parseHistory(Object? payload, RangeKey range) {
  final result = _chartResult(payload);
  final meta = _map(result['meta']) ?? const <String, dynamic>{};
  final points = parsePoints(result);

  if (points.isEmpty) {
    throw const FeedException('No price history available for this range');
  }

  // For an intraday range the day's move is measured from the previous close,
  // not from the first tick of the session — otherwise an overnight gap
  // silently disappears from the chart's headline number.
  final baseline = range == RangeKey.d1
      ? (_num(meta['chartPreviousClose']) ??
            _num(meta['previousClose']) ??
            points.first.c)
      : points.first.c;

  final last = points.last.c;
  final change = last - baseline;

  return History(
    symbol: _str(meta['symbol']) ?? '',
    range: range,
    points: points,
    currency: _str(meta['currency']) ?? 'USD',
    first: baseline,
    last: last,
    change: change,
    changePercent: baseline != 0 ? (change / baseline) * 100 : 0,
  );
}

/// Symbol types worth showing in search. Yahoo also returns futures, options
/// and non-tradable entries that this app has nothing useful to do with.
const _searchableTypes = <String>{
  'EQUITY',
  'ETF',
  'MUTUALFUND',
  'INDEX',
  'CRYPTOCURRENCY',
  'CURRENCY',
};

/// Parses the symbol lookup payload, dropping non-security hits.
List<SearchResult> parseSearch(Object? payload) {
  final root = _map(payload);
  if (root == null) return const [];

  final out = <SearchResult>[];
  for (final raw in _list(root['quotes'])) {
    final hit = _map(raw);
    if (hit == null) continue;
    final symbol = _str(hit['symbol']);
    if (symbol == null) continue;
    final type = (_str(hit['quoteType']) ?? '').toUpperCase();
    if (!_searchableTypes.contains(type)) continue;
    out.add(
      SearchResult(
        symbol: symbol,
        name: _str(hit['longname']) ?? _str(hit['shortname']) ?? symbol,
        exchange: _str(hit['exchDisp']) ?? _str(hit['exchange']) ?? '',
        type: type,
      ),
    );
  }
  return out;
}
