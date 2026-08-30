import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/types.dart';
import 'package:ticker/utils/indicators.dart';

void main() {
  group('simpleMovingAverage', () {
    test('is null until the window is full, then averages it', () {
      final ma = simpleMovingAverage([1, 2, 3, 4, 5], 3);
      expect(ma[0], isNull);
      expect(ma[1], isNull);
      expect(ma[2], closeTo(2, 1e-12)); // (1+2+3)/3
      expect(ma[3], closeTo(3, 1e-12)); // (2+3+4)/3
      expect(ma[4], closeTo(4, 1e-12)); // (3+4+5)/3
    });

    test('a period of one is the series itself', () {
      expect(simpleMovingAverage([5, 7, 9], 1), [5, 7, 9]);
    });

    test('is entirely null when the series is shorter than the period', () {
      expect(simpleMovingAverage([1, 2], 5), [null, null]);
    });

    test('the running sum does not drift over a long series', () {
      // A naive rolling sum accumulates error; check against a recomputed mean.
      final values = [for (var i = 0; i < 500; i++) 100 + (i % 7) * 1.37];
      final ma = simpleMovingAverage(values, 20);
      for (final i in [19, 100, 300, 499]) {
        final window = values.sublist(i - 19, i + 1);
        final expected = window.reduce((a, b) => a + b) / 20;
        expect(ma[i], closeTo(expected, 1e-9), reason: 'at $i');
      }
    });

    test('returns all nulls for a non-positive period', () {
      expect(simpleMovingAverage([1, 2, 3], 0), [null, null, null]);
    });
  });

  group('relativeStrengthIndex', () {
    test('needs period + 1 closes before it produces anything', () {
      // 14 closes is 13 changes — one short.
      final short = relativeStrengthIndex([
        for (var i = 0; i < 14; i++) 1.0 * i,
      ], 14);
      expect(short.every((v) => v == null), isTrue);

      final justEnough = relativeStrengthIndex([
        for (var i = 0; i < 15; i++) 1.0 * i,
      ], 14);
      expect(justEnough.take(14).every((v) => v == null), isTrue);
      expect(justEnough[14], isNotNull);
    });

    test('a series that only rises pins at 100', () {
      final rsi = relativeStrengthIndex([
        for (var i = 0; i < 30; i++) 10.0 + i,
      ], 14);
      expect(rsi[14], 100);
      expect(rsi.last, 100);
    });

    test('a series that only falls pins at 0', () {
      final rsi = relativeStrengthIndex([
        for (var i = 0; i < 30; i++) 100.0 - i,
      ], 14);
      expect(rsi[14], 0);
      expect(rsi.last, 0);
    });

    test('a dead-flat series reads neutral, not overbought', () {
      // The ratio is 0/0 here. Reporting 100 would say "maximally overbought"
      // about a line that has not moved.
      final rsi = relativeStrengthIndex(List.filled(30, 50.0), 14);
      expect(rsi[14], 50);
      expect(rsi.last, 50);
    });

    test('matches a hand-computed Wilder seed and first smoothed step', () {
      // 15 closes -> 14 changes: seven +2 gains and seven -1 losses,
      // alternating. avgGain = 14/14 = 1, avgLoss = 7/14 = 0.5.
      // RS = 2, RSI = 100 - 100/3 = 66.666...
      final closes = <double>[100];
      for (var i = 0; i < 7; i++) {
        closes.add(closes.last + 2);
        closes.add(closes.last - 1);
      }
      expect(closes, hasLength(15));

      final rsi = relativeStrengthIndex(closes, 14);
      expect(rsi[14], closeTo(200 / 3, 1e-9));
    });

    test('uses Wilder smoothing, not a simple average, after the seed', () {
      // Seed over 14 flat-ish changes, then one large gain. Wilder folds that
      // gain in at 1/14 weight; a simple 14-average would weight it 1/14 of
      // the window but also drop the oldest change, giving a different value.
      final closes = <double>[100];
      for (var i = 0; i < 14; i++) {
        closes.add(closes.last + (i.isEven ? 1 : -1));
      }
      closes.add(closes.last + 10);

      final rsi = relativeStrengthIndex(closes, 14);
      final seed = rsi[14]!;
      final next = rsi[15]!;

      // avgGain 7/14=0.5, avgLoss 7/14=0.5 -> seed is 50.
      expect(seed, closeTo(50, 1e-9));
      // Wilder: avgGain = (0.5*13 + 10)/14 = 1.1786, avgLoss = (0.5*13)/14
      // = 0.4643 -> RS 2.538 -> RSI 71.7.
      expect(next, closeTo(71.74, 0.01));
    });

    test('stays within 0 and 100 on noisy input', () {
      final closes = [
        for (var i = 0; i < 200; i++) 100 + (i * 7919 % 23) - 11.0,
      ];
      for (final v in relativeStrengthIndex(closes, 14)) {
        if (v == null) continue;
        expect(v, inInclusiveRange(0, 100));
      }
    });

    test('is all null for a non-positive period', () {
      expect(relativeStrengthIndex([1, 2, 3], 0), [null, null, null]);
    });
  });

  group('ChartWindow', () {
    test('clamps the count to the series and the screen limit', () {
      // Asking for more bars than exist settles on the whole series.
      final w = const ChartWindow(
        start: 0,
        count: 500,
      ).clampTo(total: 120, maxBars: 300);
      expect(w.count, 120);
      expect(w.start, 0);

      // Asking for more than fit settles on what fits.
      final tight = const ChartWindow(
        start: 0,
        count: 500,
      ).clampTo(total: 1000, maxBars: 200);
      expect(tight.count, 200);
    });

    test('never zooms in below the floor', () {
      final w = const ChartWindow(
        start: 0,
        count: 1,
      ).clampTo(total: 500, maxBars: 300);
      expect(w.count, ChartWindow.minBars);
    });

    test('slides a window panned past the end back into range', () {
      // The count survives; only the start moves. A window that shrank here
      // would make panning to the edge silently zoom in.
      final w = const ChartWindow(
        start: 400,
        count: 90,
      ).clampTo(total: 300, maxBars: 300);
      expect(w.count, 90);
      expect(w.end, 300);
      expect(w.start, 210);
    });

    test('cannot pan before the first bar', () {
      final w = const ChartWindow(
        start: 10,
        count: 50,
      ).panned(-999).clampTo(total: 300, maxBars: 300);
      expect(w.start, 0);
      expect(w.count, 50);
    });

    test('is empty for an empty series', () {
      final w = const ChartWindow(
        start: 0,
        count: 90,
      ).clampTo(total: 0, maxBars: 300);
      expect(w.count, 0);
      expect(w.start, 0);
    });

    test('zooming in shows fewer bars, out shows more', () {
      const w = ChartWindow(start: 100, count: 90);
      expect(w.zoomed(2).count, 45);
      expect(w.zoomed(0.5).count, 180);
    });

    test('zoom keeps the bar under the focal point in place', () {
      // Pinching on the right edge must not drag the chart leftwards.
      const w = ChartWindow(start: 100, count: 100);

      final right = w.zoomed(2, focal: 1.0);
      expect(right.end, w.end);

      final left = w.zoomed(2, focal: 0.0);
      expect(left.start, w.start);

      final middle = w.zoomed(2, focal: 0.5);
      expect(middle.start + middle.count / 2, w.start + w.count / 2);
    });

    test('ignores a degenerate zoom factor', () {
      const w = ChartWindow(start: 0, count: 50);
      expect(w.zoomed(0), w);
      expect(w.zoomed(-1), w);
      expect(w.zoomed(double.nan), w);
    });

    test('panning then clamping round-trips within the series', () {
      var w = const ChartWindow(start: 0, count: 60);
      for (final delta in [30, -10, 500, -500, 7]) {
        w = w.panned(delta).clampTo(total: 250, maxBars: 250);
        expect(w.start, greaterThanOrEqualTo(0));
        expect(w.end, lessThanOrEqualTo(250));
        expect(w.count, 60);
      }
    });
  });
}
