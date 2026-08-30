import 'dart:math' as math;

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

/// Narrowest slot a candle may occupy when fully zoomed out. Below roughly
/// this, bars stop being separable and the chart becomes a smear, so it is the
/// limit on how far out the zoom goes rather than a signal to merge bars —
/// one candle is always one day.
const minCandleSlot = 1.6;

/// Gap between candles, as a fraction of the slot each one occupies.
const _candleGapRatio = 0.25;

/// Most bars that fit legibly across [width]; the zoom-out limit.
int maxCandlesFor(double width) {
  if (width <= 0) return 0;
  return (width / minCandleSlot).floor().clamp(1, 1 << 30);
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

/// Tick values for a price axis, at round numbers inside [min]..[max].
///
/// Steps are chosen from 1, 2, 2.5 and 5 times a power of ten, so labels land
/// on values a reader recognises (120, 122.50, 125) rather than on an even
/// division of the data's own range (121.37, 123.94). [target] is a hint: the
/// rounding means the real count lands near it, not on it.
List<double> niceTicks(double min, double max, {int target = 5}) {
  if (!min.isFinite || !max.isFinite || target <= 0) return const [];
  if (max < min) return const [];
  // A flat series has no range to divide; one label at the level is honest.
  if (max == min) return [min];

  final rawStep = (max - min) / target;
  final magnitude = math
      .pow(10, (math.log(rawStep) / math.ln10).floor())
      .toDouble();
  if (magnitude <= 0 || !magnitude.isFinite) return [min];

  final normalised = rawStep / magnitude;
  final double step;
  if (normalised <= 1) {
    step = magnitude;
  } else if (normalised <= 2) {
    step = 2 * magnitude;
  } else if (normalised <= 2.5) {
    step = 2.5 * magnitude;
  } else if (normalised <= 5) {
    step = 5 * magnitude;
  } else {
    step = 10 * magnitude;
  }

  final ticks = <double>[];
  // Start at the first round value at or above the minimum.
  var value = (min / step).ceil() * step;
  // Guard against a step so small that the loop would not terminate sensibly.
  while (value <= max + step * 1e-9 && ticks.length < 100) {
    // Re-round each tick: repeated addition of a fractional step drifts, and
    // a label reading 122.50000000000001 is a visible bug.
    ticks.add((value / step).round() * step);
    value += step;
  }
  return ticks;
}

/// Decimal places an axis needs so neighbouring ticks stay distinct.
///
/// A £2.50 step needs two decimals; a £50 step needs none. Driven by the step
/// rather than the values, so every label on the axis agrees.
int axisDecimals(List<double> ticks) {
  if (ticks.length < 2) return 2;
  final step = (ticks[1] - ticks[0]).abs();
  if (step <= 0) return 2;
  for (final places in [0, 1, 2, 3, 4]) {
    final factor = math.pow(10, places);
    if ((step * factor - (step * factor).round()).abs() < 1e-6) return places;
  }
  return 4;
}
