import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/types.dart';
import 'package:ticker/utils/chart.dart';

List<PricePoint> series(List<double> values) => [
  for (var i = 0; i < values.length; i++) PricePoint(t: i, c: values[i]),
];

void main() {
  group('buildChart', () {
    test('spreads points evenly across the width and inverts the y axis', () {
      final chart = buildChart(
        series([10, 20, 30]),
        width: 100,
        height: 50,
        padding: 0,
      );

      expect(chart, isNotNull);
      expect(chart!.xs, [0, 50, 100]);
      // The lowest price sits at the bottom (y = height), the highest at the
      // top.
      expect(chart.ys, [50, 25, 0]);
      expect(chart.min, 10);
      expect(chart.max, 30);
    });

    test('insets the line by the padding so it does not clip', () {
      final chart = buildChart(
        series([1, 2]),
        width: 10,
        height: 100,
        padding: 8,
      );
      expect(chart!.ys, [92, 8]);
    });

    test('draws a flat series down the middle instead of dividing by zero', () {
      final chart = buildChart(
        series([5, 5, 5]),
        width: 90,
        height: 40,
        padding: 0,
      );
      expect(chart!.ys, [20, 20, 20]);
      expect(chart.ys.every((y) => y.isFinite), isTrue);
    });

    test('handles a single point without producing NaN', () {
      final chart = buildChart(series([42]), width: 80, height: 20, padding: 0);
      expect(chart!.xs, [0]);
      expect(chart.ys.every((y) => y.isFinite), isTrue);
    });

    test('returns null when there is nothing to draw', () {
      expect(buildChart(const [], width: 100, height: 50), isNull);
      expect(buildChart(series([1, 2]), width: 0, height: 50), isNull);
      expect(buildChart(series([1, 2]), width: 100, height: 0), isNull);
    });
  });

  group('ChartGeometry.yForPrice', () {
    final chart = buildChart(
      series([10, 30]),
      width: 100,
      height: 50,
      padding: 0,
    )!;

    test(
      'projects a price inside the range onto the same scale as the line',
      () {
        expect(chart.yForPrice(30), 0);
        expect(chart.yForPrice(10), 50);
        expect(chart.yForPrice(20), 25);
      },
    );

    test('reports null for a price the chart does not cover', () {
      // The baseline rule is simply not drawn when it falls off the chart.
      expect(chart.yForPrice(5), isNull);
      expect(chart.yForPrice(40), isNull);
      expect(chart.yForPrice(double.nan), isNull);
    });

    test('reports null for a flat series, which has no scale', () {
      final flat = buildChart(
        series([7, 7]),
        width: 100,
        height: 50,
        padding: 0,
      )!;
      expect(flat.yForPrice(7), isNull);
    });
  });

  group('nearestIndex', () {
    const xs = [0.0, 25.0, 50.0, 75.0, 100.0];

    test('finds the closest point to a touch', () {
      expect(nearestIndex(xs, 0), 0);
      expect(nearestIndex(xs, 26), 1);
      expect(nearestIndex(xs, 60), 2);
      expect(nearestIndex(xs, 99), 4);
    });

    test('clamps to the ends for touches beyond the plot', () {
      expect(nearestIndex(xs, -40), 0);
      expect(nearestIndex(xs, 400), 4);
    });

    test('reports -1 when there is no series', () {
      expect(nearestIndex(const [], 10), -1);
    });
  });
}
