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

  group('aggregateCandles', () {
    List<Candle> ramp(int n) => [
      for (var i = 0; i < n; i++)
        Candle(
          t: i,
          open: i.toDouble(),
          high: i + 2.0,
          low: i - 1.0,
          close: i + 1.0,
        ),
    ];

    test('leaves a series that already fits untouched', () {
      final candles = ramp(5);
      expect(aggregateCandles(candles, 10), same(candles));
      expect(aggregateCandles(candles, 5), same(candles));
    });

    test('merges buckets keeping first open, last close and the extremes', () {
      // Six bars into three: pairs (0,1), (2,3), (4,5).
      final merged = aggregateCandles(ramp(6), 3);
      expect(merged, hasLength(3));

      expect(merged[0].open, 0); // first bar's open
      expect(merged[0].close, 2); // second bar's close
      expect(merged[0].high, 3); // max of highs 2 and 3
      expect(merged[0].low, -1); // min of lows -1 and 0
      expect(merged[0].t, 0); // bucket starts at the first bar

      expect(merged[2].open, 4);
      expect(merged[2].close, 6);
    });

    test('never returns more buckets than asked for', () {
      // 100 into 7 needs a bucket size of 15, giving 7 buckets.
      for (final max in [1, 3, 7, 33, 99]) {
        expect(
          aggregateCandles(ramp(100), max).length,
          lessThanOrEqualTo(max),
          reason: 'max=$max',
        );
      }
    });

    test('preserves the overall open and close across the whole series', () {
      final original = ramp(50);
      final merged = aggregateCandles(original, 6);
      expect(merged.first.open, original.first.open);
      expect(merged.last.close, original.last.close);
    });

    test('is empty for a non-positive limit', () {
      expect(aggregateCandles(ramp(5), 0), isEmpty);
    });
  });
}
