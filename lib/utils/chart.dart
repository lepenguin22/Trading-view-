import '../models/types.dart';

/// Shared vertical projection for both chart forms.
mixin _PriceScale {
  double get min;
  double get max;
  double get height;
  double get padding;

  double get _usableHeight =>
      (height - padding * 2).clamp(1.0, double.infinity);

  /// Projects [price] into canvas space. Canvas y grows downward, so the
  /// highest price maps to the smallest y.
  double yFor(double price) {
    final span = max - min;
    // A dead-flat series has no range to scale against; draw it down the middle.
    final ratio = span == 0 ? 0.5 : (price - min) / span;
    return padding + (1 - ratio) * _usableHeight;
  }

  /// Like [yFor], but null when the price falls outside the drawn range or the
  /// series is flat. Used for the baseline rule, which is simply not drawn
  /// when it would sit off the chart.
  double? yForPrice(double price) {
    if (!price.isFinite || price < min || price > max) return null;
    if (max - min == 0) return null;
    return yFor(price);
  }
}

/// A close-price series projected onto a drawing viewport.
class ChartGeometry with _PriceScale {
  ChartGeometry({
    required this.xs,
    required this.ys,
    required this.min,
    required this.max,
    required this.height,
    required this.padding,
  });

  /// Horizontal position of each point, so callers can hit-test a touch.
  final List<double> xs;

  /// Vertical position of each point, in canvas coordinates.
  final List<double> ys;

  @override
  final double min;
  @override
  final double max;
  @override
  final double height;
  @override
  final double padding;
}

/// A candlestick series projected onto a drawing viewport.
class CandleGeometry with _PriceScale {
  CandleGeometry({
    required this.xs,
    required this.bodyWidth,
    required this.min,
    required this.max,
    required this.height,
    required this.padding,
  });

  /// Horizontal centre of each candle.
  final List<double> xs;

  /// Width of a candle body. The wick is drawn down the centre.
  final double bodyWidth;

  @override
  final double min;
  @override
  final double max;
  @override
  final double height;
  @override
  final double padding;
}

/// Projects a series of close prices onto a viewport of [width] x [height].
///
/// Points are spaced evenly by index rather than by timestamp: market data has
/// overnight and weekend gaps, and spacing by time would leave the chart mostly
/// empty air. This matches how every trading app draws it.
///
/// [padding] is a vertical inset so the line never clips against the top or
/// bottom edge.
ChartGeometry? buildChart(
  List<double> values, {
  required double width,
  required double height,
  double padding = 4,
}) {
  if (values.isEmpty || width <= 0 || height <= 0) return null;

  var min = values.first;
  var max = values.first;
  for (final v in values) {
    if (v < min) min = v;
    if (v > max) max = v;
  }

  final chart = ChartGeometry(
    xs: [],
    ys: [],
    min: min,
    max: max,
    height: height,
    padding: padding,
  );

  for (var i = 0; i < values.length; i++) {
    // A single point sits at the left edge rather than dividing by zero.
    chart.xs.add(values.length == 1 ? 0.0 : (i / (values.length - 1)) * width);
    chart.ys.add(chart.yFor(values[i]));
  }
  return chart;
}

/// Smallest candle body that still reads as a candle rather than a smear.
const minBodyWidth = 3.0;

/// Gap between candles, as a fraction of the slot each one occupies.
const _candleGapRatio = 0.25;

/// How many candles fit legibly across [width].
///
/// Callers aggregate their series down to this before building the geometry,
/// so a 5Y weekly series becomes readable bars rather than a solid block.
int maxCandlesFor(double width) {
  if (width <= 0) return 0;
  final slot = minBodyWidth / (1 - _candleGapRatio);
  return (width / slot).floor().clamp(1, 1 << 30);
}

/// Projects [candles] onto a viewport of [width] x [height].
///
/// Unlike the line chart, the vertical range spans every high and low rather
/// than just the closes — a wick that ran outside the closing range must still
/// be drawn inside the viewport.
CandleGeometry? buildCandleChart(
  List<Candle> candles, {
  required double width,
  required double height,
  double padding = 4,
}) {
  if (candles.isEmpty || width <= 0 || height <= 0) return null;

  var min = candles.first.low;
  var max = candles.first.high;
  for (final candle in candles) {
    if (candle.low < min) min = candle.low;
    if (candle.high > max) max = candle.high;
  }

  final slot = width / candles.length;
  final bodyWidth = (slot * (1 - _candleGapRatio)).clamp(1.0, 24.0);

  return CandleGeometry(
    // Centred in its slot, so the first and last candles sit fully on screen
    // instead of being half clipped by the edges.
    xs: [for (var i = 0; i < candles.length; i++) slot * (i + 0.5)],
    bodyWidth: bodyWidth,
    min: min,
    max: max,
    height: height,
    padding: padding,
  );
}

/// Index of the point nearest a touch x, for the scrubbing crosshair.
int nearestIndex(List<double> xs, double x) {
  if (xs.isEmpty) return -1;
  var best = 0;
  var bestDistance = (xs[0] - x).abs();
  for (var i = 1; i < xs.length; i++) {
    final distance = (xs[i] - x).abs();
    if (distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}
