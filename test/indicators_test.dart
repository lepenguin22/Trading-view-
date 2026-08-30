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

  group('sampleBuckets', () {
    test('is a no-op when nothing is aggregated', () {
      final source = <double?>[1, 2, 3];
      expect(sampleBuckets(source, 1), same(source));
    });

    test('takes each bucket final value, aligning with the bucket close', () {
      // The indicator value drawn on a merged bar must be the one at that
      // bar's closing tick, not its first.
      expect(sampleBuckets<double?>([1, 2, 3, 4, 5, 6], 2), [2, 4, 6]);
      expect(sampleBuckets<double?>([1, 2, 3, 4, 5], 2), [2, 4, 5]);
    });

    test('carries nulls through from the warm-up region', () {
      expect(sampleBuckets<double?>([null, null, 3, 4], 2), [null, 4]);
    });
  });

  group('bucketSizeFor', () {
    test('is one when the series already fits', () {
      expect(bucketSizeFor(10, 20), 1);
      expect(bucketSizeFor(20, 20), 1);
    });

    test('rounds up so the bucket count never exceeds the limit', () {
      expect(bucketSizeFor(100, 7), 15);
      expect((100 / 15).ceil(), lessThanOrEqualTo(7));
    });

    test('is one for degenerate inputs', () {
      expect(bucketSizeFor(0, 10), 1);
      expect(bucketSizeFor(10, 0), 1);
    });

    test('agrees with what aggregateCandles actually produces', () {
      final candles = [
        for (var i = 0; i < 137; i++)
          Candle(t: i, open: 1, high: 2, low: 0, close: 1),
      ];
      const maxCount = 40;
      final merged = aggregateCandles(candles, maxCount);
      final size = bucketSizeFor(candles.length, maxCount);
      // The indicator sampler must produce exactly one value per drawn bar.
      expect(
        sampleBuckets<double?>(List.filled(candles.length, 1), size),
        hasLength(merged.length),
      );
    });
  });
}
