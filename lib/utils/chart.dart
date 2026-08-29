import '../models/types.dart';

/// A price series projected onto a drawing viewport.
class ChartGeometry {
  const ChartGeometry({
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

  /// Lowest and highest close in the series.
  final double min;
  final double max;

  final double height;
  final double padding;

  /// Projects an arbitrary price into chart space, or null when it falls
  /// outside the drawn range. Used for the baseline rule.
  double? yForPrice(double price) {
    if (!price.isFinite || price < min || price > max) return null;
    final span = max - min;
    if (span == 0) return null;
    final usableHeight = (height - padding * 2).clamp(1.0, double.infinity);
    return padding + (1 - (price - min) / span) * usableHeight;
  }
}

/// Projects a price series onto a viewport of [width] x [height].
///
/// Points are spaced evenly by index rather than by timestamp: market data has
/// overnight and weekend gaps, and spacing by time would leave the chart mostly
/// empty air. This matches how every trading app draws it.
///
/// [padding] is a vertical inset so the line never clips against the top or
/// bottom edge.
ChartGeometry? buildChart(
  List<PricePoint> points, {
  required double width,
  required double height,
  double padding = 4,
}) {
  if (points.isEmpty || width <= 0 || height <= 0) return null;

  var min = points.first.c;
  var max = points.first.c;
  for (final p in points) {
    if (p.c < min) min = p.c;
    if (p.c > max) max = p.c;
  }

  // A dead-flat series has no range to scale against; draw it down the middle.
  final span = max - min;
  final usableHeight = (height - padding * 2).clamp(1.0, double.infinity);

  final xs = <double>[];
  final ys = <double>[];
  for (var i = 0; i < points.length; i++) {
    // A single point sits at the left edge rather than dividing by zero.
    final x = points.length == 1 ? 0.0 : (i / (points.length - 1)) * width;
    final ratio = span == 0 ? 0.5 : (points[i].c - min) / span;
    // Canvas y grows downward, so the highest price maps to the smallest y.
    ys.add(padding + (1 - ratio) * usableHeight);
    xs.add(x);
  }

  return ChartGeometry(
    xs: xs,
    ys: ys,
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
