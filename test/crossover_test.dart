import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/crossover.dart';
import 'package:ticker/utils/indicators.dart';

void main() {
  group('crossings', () {
    test('finds an upward cross on the bar the sign changes', () {
      final crosses = crossings([1, 2, 4, 6], [5, 5, 5, 5]);

      // Differences run -4, -3, -1, +1: the sign turns on the last bar, not
      // on the one where the gap merely narrows.
      expect(crosses.length, 1);
      expect(crosses.single.index, 3);
      expect(crosses.single.direction, CrossDirection.up);
    });

    test('finds a downward cross', () {
      final crosses = crossings([9, 8, 4, 1], [5, 5, 5, 5]);

      expect(crosses.single.index, 2);
      // 9, 8 are above; 4 is the first below.
      expect(crosses.single.direction, CrossDirection.down);
    });

    test('reports both directions in order', () {
      final crosses = crossings([1, 6, 7, 2, 1], [5, 5, 5, 5, 5]);

      expect(crosses.map((c) => (c.index, c.direction)), [
        (1, CrossDirection.up),
        (3, CrossDirection.down),
      ]);
    });

    test('a series that never crosses reports nothing', () {
      expect(crossings([1, 2, 3, 4], [5, 5, 5, 5]), isEmpty);
    });

    test('the first bar with both values is not itself a cross', () {
      // Fast starts above slow. Without an earlier relationship there is
      // nothing for it to have crossed.
      expect(crossings([9, 9, 9], [5, 5, 5]), isEmpty);
    });

    test('touching without passing through is not a cross', () {
      // Comes down to meet the slow line exactly, then turns back up.
      final crosses = crossings([9, 7, 5, 7, 9], [5, 5, 5, 5, 5]);

      expect(crosses, isEmpty);
    });

    test('touching and then passing through is one cross, not two', () {
      final crosses = crossings([9, 7, 5, 3, 1], [5, 5, 5, 5, 5]);

      expect(crosses.length, 1);
      expect(crosses.single.index, 3);
      expect(crosses.single.direction, CrossDirection.down);
    });

    test('leading nulls are skipped rather than read as a cross', () {
      final crosses = crossings([null, null, 1, 9], [null, null, 5, 5]);

      expect(crosses.single.index, 3);
      expect(crosses.single.direction, CrossDirection.up);
    });

    test('a gap resets, so no cross is dated to a bar with no value', () {
      // Below, then a gap, then above: the crossing happened somewhere in the
      // gap and cannot honestly be pinned to a bar.
      expect(crossings([1, null, 9], [5, null, 5]), isEmpty);
    });

    test('stops at the shorter of the two series', () {
      expect(crossings([1, 9, 1], [5, 5]), [
        (index: 1, direction: CrossDirection.up),
      ]);
    });

    test('a non-finite value is treated as a gap, not a cross', () {
      expect(crossings([1, double.nan, 9], [5, 5, 5]), isEmpty);
    });

    test('empty input is empty output', () {
      expect(crossings(const [], const []), isEmpty);
    });
  });

  group('crossingsFor', () {
    /// Falls for 200 bars and then rises for 200. The fall leaves the fast
    /// average below the slow one, and the rise pulls it back through — so
    /// there is a real upward cross to find, at a bar both averages exist on.
    final valley = <double>[
      for (var i = 0; i < 200; i++) 300 - i.toDouble(),
      for (var i = 0; i < 200; i++) 100 + i.toDouble(),
    ];

    /// Rises from the first bar. Included because it is the case that catches
    /// a naive implementation: by the time the 200 average exists the fast one
    /// is already above it, so there is nothing to cross and the honest answer
    /// is no crossings at all.
    final rising = [for (var i = 0; i < 300; i++) 100 + i.toDouble()];

    Map<int, List<double?>> masOf(List<double> closes) => {
      for (final period in maPeriods)
        period: simpleMovingAverage(closes, period),
    };

    test('50/200 finds the golden cross on a rising series', () {
      final spec = crossoverSpecs.firstWhere((s) => s.id == 'ma50x200');
      final crosses = crossingsFor(
        spec,
        closes: valley,
        movingAverages: masOf(valley),
      );

      expect(crosses, isNotEmpty);
      expect(crosses.every((c) => c.direction == CrossDirection.up), isTrue);
      // The 200 SMA does not exist before bar 199, so nothing can be dated
      // earlier than that.
      expect(crosses.first.index, greaterThanOrEqualTo(199));
    });

    test('price/200 crosses above on the same rising series', () {
      final spec = crossoverSpecs.firstWhere((s) => s.id == 'closex200');
      final crosses = crossingsFor(
        spec,
        closes: valley,
        movingAverages: masOf(valley),
      );

      expect(crosses, isNotEmpty);
      expect(crosses.first.direction, CrossDirection.up);
    });

    test(
      'a series already above when the slow average appears never crosses',
      () {
        for (final spec in crossoverSpecs) {
          expect(
            crossingsFor(spec, closes: rising, movingAverages: masOf(rising)),
            isEmpty,
            reason: '${spec.id} has nothing to cross on a monotonic rise',
          );
        }
      },
    );

    test('a missing moving average yields nothing rather than throwing', () {
      final spec = crossoverSpecs.first;

      expect(
        crossingsFor(spec, closes: rising, movingAverages: const {}),
        isEmpty,
      );
    });

    test('a series too short for the slow average yields nothing', () {
      final short = [for (var i = 0; i < 60; i++) 100 + i.toDouble()];

      for (final spec in crossoverSpecs) {
        expect(
          crossingsFor(spec, closes: short, movingAverages: masOf(short)),
          isEmpty,
          reason: '${spec.id} needs ${spec.slowPeriod} bars',
        );
      }
    });
  });

  group('crossoverSpecs', () {
    test('every spec names both directions distinctly', () {
      for (final spec in crossoverSpecs) {
        expect(spec.upLabel, isNotEmpty);
        expect(spec.downLabel, isNotEmpty);
        expect(spec.upLabel, isNot(spec.downLabel));
        expect(spec.labelFor(CrossDirection.up), spec.upLabel);
        expect(spec.labelFor(CrossDirection.down), spec.downLabel);
      }
    });

    test('ids are unique, since they key what is switched on', () {
      final ids = crossoverSpecs.map((s) => s.id).toSet();

      expect(ids.length, crossoverSpecs.length);
    });

    test('every period a spec needs is one the chart already computes', () {
      for (final spec in crossoverSpecs) {
        for (final period in spec.periods) {
          expect(
            maPeriods,
            contains(period),
            reason: '${spec.id} needs an MA$period the chart does not draw',
          );
        }
      }
    });
  });
}
