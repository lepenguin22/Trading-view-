import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/cpf_allocation.dart';

void main() {
  group('cpfAllocationFor', () {
    test('matches the published table, band by band', () {
      // Percentages of wage, effective 1 January 2026. Cross-checked against
      // the published allocation *ratios*, which reproduce these exactly at a
      // 37% total — see the library doc for the arithmetic.
      expect(cpfAllocationFor(30), (oa: 23.0, sa: 6.0, ma: 8.0));
      expect(cpfAllocationFor(40), (oa: 21.0, sa: 7.0, ma: 9.0));
      expect(cpfAllocationFor(48), (oa: 19.0, sa: 8.0, ma: 10.0));
      expect(cpfAllocationFor(53), (oa: 15.0, sa: 11.5, ma: 10.5));
    });

    test('every band totals 37% of wage', () {
      // The bands move money between accounts; they do not change how much
      // reaches CPF. A band that failed this would be a transcription slip.
      for (final age in [25, 35, 36, 45, 46, 50, 51, 55]) {
        final a = cpfAllocationFor(age);
        expect(
          a.oa + a.sa + a.ma,
          closeTo(37, 0.001),
          reason: 'age $age does not total 37%',
        );
      }
    });

    test('a band includes its upper age, and the next starts after it', () {
      // CPF's "35 & below" covers 35; "above 35 to 45" starts at 36.
      expect(cpfAllocationFor(35), cpfAllocationFor(30));
      expect(cpfAllocationFor(36), isNot(cpfAllocationFor(35)));
      expect(cpfAllocationFor(45), cpfAllocationFor(40));
      expect(cpfAllocationFor(46), isNot(cpfAllocationFor(45)));
      expect(cpfAllocationFor(50), cpfAllocationFor(48));
      expect(cpfAllocationFor(51), isNot(cpfAllocationFor(50)));
    });

    test('the Ordinary share falls and MediSave rises with age', () {
      // The shape of the table, independent of its exact figures: a slip that
      // kept the totals right but swapped two accounts would fail here.
      var previousOa = double.infinity;
      var previousMa = 0.0;
      for (final age in [30, 40, 48, 53]) {
        final a = cpfAllocationFor(age);
        expect(a.oa, lessThan(previousOa));
        expect(a.ma, greaterThan(previousMa));
        previousOa = a.oa;
        previousMa = a.ma;
      }
    });
  });

  group('projectionPassesCoveredAges', () {
    test('flags a projection that outruns the table', () {
      expect(projectionPassesCoveredAges(30, 20), isFalse);
      expect(projectionPassesCoveredAges(30, 25), isFalse);
      expect(projectionPassesCoveredAges(30, 26), isTrue);
      expect(projectionPassesCoveredAges(56, 1), isTrue);
    });

    test('says nothing when no age was given', () {
      // Without an age the shares are typed in by hand, so the table is not
      // being relied on and has nothing to warn about.
      expect(projectionPassesCoveredAges(0, 40), isFalse);
    });
  });
}
