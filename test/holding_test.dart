import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/holding.dart';

void main() {
  group('marginOfSafetyAt', () {
    const valued = Holding(symbol: 'AAA', dcfValue: 100);

    test('measures the gap as a fraction of fair value', () {
      // 100 fair, 80 asked: a fifth of the valuation is the buyer's cushion.
      expect(valued.marginOfSafetyAt(80), closeTo(0.2, 1e-9));
      expect(valued.marginOfSafetyAt(100), 0);
    });

    test('goes negative when the price is over the valuation', () {
      // Not clamped at zero: "no margin of safety" and "25% beyond what it is
      // worth" are different facts, and the second is the one worth seeing.
      expect(valued.marginOfSafetyAt(125), closeTo(-0.25, 1e-9));
    });

    test('is a fraction of fair value, not of price', () {
      // The two agree in direction and never in size. Dividing by price would
      // call 50 against a fair 100 a margin of 100% rather than 50%.
      expect(valued.marginOfSafetyAt(50), closeTo(0.5, 1e-9));
    });

    test('says nothing rather than zero when there is no valuation', () {
      // A zero would claim the price sits exactly on a fair value the sheet
      // never gave.
      const unvalued = Holding(symbol: 'AAA');
      expect(unvalued.marginOfSafetyAt(80), isNull);
    });

    test('refuses a price or valuation it cannot divide by', () {
      expect(valued.marginOfSafetyAt(0), isNull);
      expect(valued.marginOfSafetyAt(-10), isNull);
      expect(valued.marginOfSafetyAt(double.nan), isNull);
      expect(valued.marginOfSafetyAt(double.infinity), isNull);
      expect(
        const Holding(symbol: 'A', dcfValue: 0).marginOfSafetyAt(10),
        isNull,
      );
    });
  });

  group('hasAnalysis', () {
    test('a valuation alone is enough to show the tier', () {
      // Scores and a valuation arrive independently: a holding with one and
      // not the other still has something to say.
      expect(const Holding(symbol: 'A', dcfValue: 100).hasAnalysis, isTrue);
      expect(const Holding(symbol: 'A', dcfValue: 100).hasScores, isFalse);
      expect(const Holding(symbol: 'A').hasAnalysis, isFalse);
    });
  });

  group('storage round trip', () {
    test('a valuation survives being saved and read back', () {
      const holding = Holding(symbol: 'AAA', shares: 10, dcfValue: 420.5);
      expect(Holding.fromJson(holding.toJson())!.dcfValue, 420.5);
    });

    test('a stored zero or negative is refused on the way back in', () {
      // Re-checked on load, not only on parse: a bad value written by any
      // route must not reach the arithmetic.
      for (final bad in [0, -1, 'four hundred']) {
        expect(
          Holding.fromJson({'symbol': 'AAA', 'dcfValue': bad})!.dcfValue,
          isNull,
          reason: '$bad is not a fair value',
        );
      }
    });

    test('a holding without one writes no key at all', () {
      expect(
        const Holding(symbol: 'AAA').toJson(),
        isNot(contains('dcfValue')),
      );
    });
  });
}
