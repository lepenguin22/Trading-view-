import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/types.dart';
import 'package:ticker/utils/chart.dart';

/// buildChart works on bare close prices, so a series is just its values.
List<double> series(List<double> values) => values;

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

  group('maxCandlesFor', () {
    test('scales with the available width', () {
      // Each candle needs minBodyWidth plus its share of the gap.
      expect(maxCandlesFor(400), greaterThan(maxCandlesFor(200)));
      expect(maxCandlesFor(0), 0);
    });

    test('always leaves room for at least one candle', () {
      expect(maxCandlesFor(1), 1);
    });
  });

  group('buildCandleChart', () {
    Candle bar(double o, double h, double l, double c, [int t = 0]) =>
        Candle(t: t, open: o, high: h, low: l, close: c);

    test('spans every high and low, not just the closes', () {
      // The closes sit in 10..12, but a wick ran to 20 and another to 5.
      final chart = buildCandleChart(
        [bar(10, 20, 9, 11), bar(11, 13, 5, 12)],
        width: 100,
        height: 50,
      )!;
      expect(chart.min, 5);
      expect(chart.max, 20);
    });

    test('centres each candle in its slot so the edges are not clipped', () {
      final chart = buildCandleChart(
        [bar(1, 2, 0, 1), bar(1, 2, 0, 1)],
        width: 100,
        height: 50,
      )!;
      // Two candles, 50px slots, centres at 25 and 75.
      expect(chart.xs, [25, 75]);
      expect(chart.bodyWidth, lessThan(50));
      expect(chart.bodyWidth, greaterThan(0));
    });

    test('projects highs above lows on the canvas', () {
      final chart = buildCandleChart(
        [bar(10, 20, 5, 15)],
        width: 100,
        height: 50,
        padding: 0,
      )!;
      // Canvas y grows downward, so the high has the smaller y.
      expect(chart.yFor(20), lessThan(chart.yFor(5)));
      expect(chart.yFor(20), 0);
      expect(chart.yFor(5), 50);
    });

    test('returns null when there is nothing to draw', () {
      expect(buildCandleChart(const [], width: 100, height: 50), isNull);
      expect(buildCandleChart([bar(1, 2, 0, 1)], width: 0, height: 50), isNull);
    });
  });

  group('niceTicks', () {
    test('lands on round numbers, not on divisions of the raw range', () {
      // A reader recognises 120 and 125; 121.37 is noise.
      final ticks = niceTicks(119.4, 137.8, target: 5);
      expect(ticks, isNotEmpty);
      for (final t in ticks) {
        expect(t % 5, closeTo(0, 1e-9), reason: '$t is not a round step');
      }
      expect(ticks.first, greaterThanOrEqualTo(119.4));
      expect(ticks.last, lessThanOrEqualTo(137.8));
    });

    test('produces roughly the requested number of ticks', () {
      for (final range in [
        [0.0, 1.0],
        [99.0, 101.0],
        [1200.0, 4800.0],
        [0.0012, 0.0089],
      ]) {
        final ticks = niceTicks(range[0], range[1], target: 5);
        expect(ticks.length, inInclusiveRange(2, 12), reason: '$range');
      }
    });

    test('every tick sits inside the range', () {
      final ticks = niceTicks(37.2, 41.9);
      for (final t in ticks) {
        expect(t, inInclusiveRange(37.2, 41.9));
      }
    });

    test('does not accumulate floating point drift', () {
      // Repeated addition of 2.5 is where a naive loop produces 122.50000001.
      final ticks = niceTicks(100, 125, target: 10);
      for (final t in ticks) {
        expect(
          (t * 100 - (t * 100).round()).abs(),
          lessThan(1e-6),
          reason: '$t has drifted',
        );
      }
    });

    test('a flat range yields the single level rather than nothing', () {
      expect(niceTicks(50, 50), [50]);
    });

    test('is empty for degenerate input', () {
      expect(niceTicks(double.nan, 10), isEmpty);
      expect(niceTicks(10, double.infinity), isEmpty);
      expect(niceTicks(10, 5), isEmpty, reason: 'max below min');
      expect(niceTicks(1, 10, target: 0), isEmpty);
    });

    test('handles sub-unit prices without collapsing', () {
      final ticks = niceTicks(0.0421, 0.0468);
      expect(ticks.length, greaterThan(1));
      expect(ticks.first, greaterThanOrEqualTo(0.0421));
    });
  });

  group('axisDecimals', () {
    test('uses no decimals for a whole-number step', () {
      expect(axisDecimals([100, 110, 120]), 0);
    });

    test('uses enough decimals to keep a fractional step distinct', () {
      expect(axisDecimals([100, 102.5, 105]), 1);
      expect(axisDecimals([1.00, 1.05, 1.10]), 2);
    });

    test('falls back to two places when there is no step to read', () {
      expect(axisDecimals(const []), 2);
      expect(axisDecimals(const [42]), 2);
    });
  });
}
