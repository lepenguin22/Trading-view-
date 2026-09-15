import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/projection.dart';
import 'package:ticker/utils/retirement_sums.dart';

void main() {
  group('retirementSumsFor', () {
    test('matches the published 2026 cohort', () {
      final sums = retirementSumsFor(2026);

      expect(sums.brs, closeTo(110200, 0.01));
      expect(sums.frs, closeTo(220400, 0.01));
      expect(sums.ers, closeTo(440800, 0.01));
    });

    test('reproduces the announced 2027 cohort from the 3.5% schedule', () {
      // Published as $114,100 for the 2027 cohort. Growing the 2026 figure by
      // the announced rate lands there, which is the check that the rate and
      // the base belong to each other.
      final sums = retirementSumsFor(2027);

      expect(sums.brs, closeTo(114100, 100));
      expect(sums.frs, closeTo(228200, 100));
      expect(sums.ers, closeTo(456400, 400));
    });

    test('a later cohort faces a much larger sum', () {
      // The trap this exists for: someone turning 55 in 2053 measured against
      // 2026's Full sum would clear it on paper and miss it by half in life.
      final later = retirementSumsFor(2053);

      expect(later.brs, greaterThan(retirementSumsFor(2026).brs * 2));
    });

    test('a cohort before the base is scaled back, not forward', () {
      expect(retirementSumsFor(2025).brs, lessThan(110200));
    });

    test('Full is always twice Basic, whatever the base and rate', () {
      final sums = retirementSumsFor(2040, base: 90000, growthPercent: 2);
      expect(sums.frs, closeTo(sums.brs * 2, 0.01));
    });

    test('reproduces the published Basic sums across announced cohorts', () {
      // The whole announced schedule, as a check on the base and the rate
      // together. CPF's own site is unreachable from here, so this table is
      // the closest thing to the source that can live in the repo.
      const published = {
        2023: 99400.0,
        2024: 102900.0,
        2025: 106500.0,
        2026: 110200.0,
        2027: 114100.0,
      };
      for (final entry in published.entries) {
        expect(
          retirementSumsFor(entry.key).brs,
          closeTo(entry.value, 500),
          reason: 'the ${entry.key} cohort',
        );
      }
    });

    test('the Enhanced multiple changed in 2025 and is not assumed', () {
      // Three times the Basic until 2025, four from it. Encoded rather than
      // treated as arithmetic: it is policy that has already moved once.
      expect(retirementSumsFor(2024).ers, closeTo(102900 * 3, 1600));
      expect(retirementSumsFor(2026).ers, closeTo(110200 * 4, 0.01));
      expect(ersMultipleFor(2024), 3);
      expect(ersMultipleFor(2025), 4);
    });
  });

  group('cohortYearFor and isExtrapolated', () {
    test('finds the year someone turns 55', () {
      expect(cohortYearFor(30, 2026), 2051);
      expect(cohortYearFor(54, 2026), 2027);
      expect(cohortYearFor(55, 2026), 2026);
    });

    test('flags cohorts past the announced schedule', () {
      expect(isExtrapolated(2027), isFalse);
      expect(isExtrapolated(2028), isTrue);
      expect(isExtrapolated(2051), isTrue);
    });
  });

  group('checkRetirementSums', () {
    ProjectionInput at(int age, int years) => ProjectionInput(
      grossMonthlySalary: 10000,
      currentAge: age,
      startingOa: 50000,
      startingSa: 20000,
      startingMa: 30000,
      oaReturnPercent: 0,
      saReturnPercent: 0,
      maReturnPercent: 0,
      years: years,
    );

    test('counts Ordinary and Special only, never MediSave', () {
      // The Retirement Account is formed from SA then OA. MediSave stays put,
      // so counting it would clear the bar with ineligible money.
      final input = at(54, 5);
      final check = checkRetirementSums(project(input), input, 2026)!;
      final at55 = project(input)[12];

      expect(check.eligible, closeTo(at55.oa + at55.sa, 0.01));
      expect(check.eligible, isNot(closeTo(at55.total, 0.01)));
      expect(check.excludedMediSave, closeTo(at55.ma, 0.01));
    });

    test('measures at 55, not at the end of the projection', () {
      // A projection running to 70 must still be judged at 55, where the bar
      // actually sits.
      final input = at(50, 20);
      final points = project(input);
      final check = checkRetirementSums(points, input, 2026)!;

      expect(check.eligible, closeTo(points[60].oa + points[60].sa, 0.01));
      expect(check.eligible, lessThan(points.last.oa + points.last.sa));
    });

    test('says nothing when the projection stops before 55', () {
      // A balance at 40 says nothing about a bar measured at 55, and comparing
      // them anyway would be the most flattering possible error.
      final input = at(30, 5);
      expect(checkRetirementSums(project(input), input, 2026), isNull);
    });

    test('says nothing without an age', () {
      const input = ProjectionInput(grossMonthlySalary: 10000, years: 40);
      expect(checkRetirementSums(project(input), input, 2026), isNull);
    });

    test('uses the cohort year, not the year it is run in', () {
      final input = at(30, 30);
      final check = checkRetirementSums(project(input), input, 2026)!;

      expect(check.cohortYear, 2051);
      expect(check.sums.brs, closeTo(retirementSumsFor(2051).brs, 0.01));
    });
  });
}
