import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/projection.dart';

void main() {
  group('take-home', () {
    test('is gross less the employee share', () {
      // The 4,300 → 3,440 in a real payslip: 20% employee CPF.
      const input = ProjectionInput(
        grossMonthlySalary: 4300,
        employeeCpfPercent: 20,
      );

      expect(input.takeHome, closeTo(3440, 0.01));
    });

    test('ignores the employer share, which never reaches pay', () {
      const a = ProjectionInput(
        grossMonthlySalary: 4300,
        employeeCpfPercent: 20,
        employerCpfPercent: 17,
      );
      const b = ProjectionInput(
        grossMonthlySalary: 4300,
        employeeCpfPercent: 20,
        employerCpfPercent: 0,
      );

      expect(a.takeHome, b.takeHome);
    });

    test('flags a plan that invests more than take-home allows', () {
      const overspending = ProjectionInput(
        grossMonthlySalary: 4300,
        employeeCpfPercent: 20,
        monthlyInvestment: 4000,
      );
      const affordable = ProjectionInput(
        grossMonthlySalary: 4300,
        employeeCpfPercent: 20,
        monthlyInvestment: 900,
      );

      expect(overspending.investsBeyondTakeHome, isTrue);
      expect(overspending.remainingAfterInvesting, closeTo(-560, 0.01));
      expect(affordable.investsBeyondTakeHome, isFalse);
      expect(affordable.remainingAfterInvesting, closeTo(2540, 0.01));
    });
  });

  group('compounding', () {
    test('a lump sum with no contributions matches the closed form', () {
      const input = ProjectionInput(
        startingInvestments: 10000,
        investmentReturnPercent: 6,
        years: 10,
        cpfReturnPercent: 0,
      );

      // 10000 * (1 + 0.06/12) ^ 120
      final expected = 10000 * math.pow(1 + 0.06 / 12, 120);
      expect(project(input).last.invested, closeTo(expected, 0.01));
    });

    test('regular contributions match the annuity formula', () {
      const input = ProjectionInput(
        monthlyInvestment: 500,
        investmentReturnPercent: 6,
        years: 10,
        cpfReturnPercent: 0,
      );

      // Ordinary annuity: PMT * ((1+r)^n - 1) / r
      const r = 0.06 / 12;
      final expected = 500 * (math.pow(1 + r, 120) - 1) / r;
      expect(project(input).last.invested, closeTo(expected, 0.01));
    });

    test('a zero return returns exactly what was paid in', () {
      const input = ProjectionInput(
        startingInvestments: 1000,
        monthlyInvestment: 100,
        investmentReturnPercent: 0,
        cpfReturnPercent: 0,
        years: 5,
      );

      final last = project(input).last;
      expect(last.invested, closeTo(1000 + 100 * 60, 0.01));
      expect(last.contributedToInvestments, closeTo(6000, 0.01));
    });

    test('starts at the opening position, before any contribution', () {
      const input = ProjectionInput(
        startingInvestments: 1000,
        startingCpf: 2000,
        monthlyInvestment: 100,
      );
      final first = project(input).first;

      expect(first.month, 0);
      expect(first.invested, 1000);
      expect(first.cpf, 2000);
      expect(first.contributedToInvestments, 0);
    });

    test('a zero-year projection is just the opening position', () {
      const input = ProjectionInput(startingInvestments: 1000, years: 0);

      // A chart still needs a point to draw.
      expect(project(input), hasLength(1));
      expect(project(input).single.invested, 1000);
    });

    test('runs one point per month plus the opening one', () {
      expect(project(const ProjectionInput(years: 3)), hasLength(37));
    });
  });

  group('CPF', () {
    test('both shares reach CPF, only the employee share leaves pay', () {
      const input = ProjectionInput(
        grossMonthlySalary: 1000,
        employeeCpfPercent: 20,
        employerCpfPercent: 17,
        cpfReturnPercent: 0,
        years: 1,
      );

      final last = project(input).last;
      // 37% of 1000, twelve times.
      expect(last.cpf, closeTo(370 * 12, 0.01));
      expect(last.takeHome, closeTo(800, 0.01));
    });

    test('the wage ceiling caps the contribution', () {
      const uncapped = ProjectionInput(
        grossMonthlySalary: 10000,
        employeeCpfPercent: 20,
        employerCpfPercent: 17,
        cpfReturnPercent: 0,
        years: 1,
      );
      const capped = ProjectionInput(
        grossMonthlySalary: 10000,
        employeeCpfPercent: 20,
        employerCpfPercent: 17,
        cpfSalaryCeiling: 7400,
        cpfReturnPercent: 0,
        years: 1,
      );

      expect(project(uncapped).last.cpf, closeTo(3700 * 12, 0.01));
      expect(project(capped).last.cpf, closeTo(7400 * 0.37 * 12, 0.01));
    });

    test('a ceiling above the salary changes nothing', () {
      const input = ProjectionInput(
        grossMonthlySalary: 4300,
        cpfSalaryCeiling: 7400,
        cpfReturnPercent: 0,
        years: 2,
      );
      const noCeiling = ProjectionInput(
        grossMonthlySalary: 4300,
        cpfReturnPercent: 0,
        years: 2,
      );

      expect(
        project(input).last.cpf,
        closeTo(project(noCeiling).last.cpf, 0.01),
      );
    });

    test('the two pots compound at their own rates', () {
      // Same money in each, different rates: the balances must diverge.
      const input = ProjectionInput(
        startingInvestments: 10000,
        startingCpf: 10000,
        investmentReturnPercent: 7,
        cpfReturnPercent: 2.5,
        years: 10,
      );

      final last = project(input).last;
      expect(last.invested, greaterThan(last.cpf));
      expect(last.total, closeTo(last.invested + last.cpf, 0.01));
    });
  });

  group('salary growth', () {
    test('a rise lands once a year, not every month', () {
      const input = ProjectionInput(
        grossMonthlySalary: 1000,
        salaryGrowthPercent: 10,
        years: 3,
      );
      final points = project(input);

      // Months 1-12 at the starting salary, 13-24 after one rise.
      expect(points[1].grossSalary, closeTo(1000, 0.01));
      expect(points[12].grossSalary, closeTo(1000, 0.01));
      expect(points[13].grossSalary, closeTo(1100, 0.01));
      expect(points[25].grossSalary, closeTo(1210, 0.01));
    });

    test('growth raises CPF contributions with it', () {
      const flat = ProjectionInput(
        grossMonthlySalary: 1000,
        cpfReturnPercent: 0,
        years: 5,
      );
      const growing = ProjectionInput(
        grossMonthlySalary: 1000,
        salaryGrowthPercent: 5,
        cpfReturnPercent: 0,
        years: 5,
      );

      expect(project(growing).last.cpf, greaterThan(project(flat).last.cpf));
    });

    test('growth carries a salary through the ceiling', () {
      // The reason the ceiling is worth having even below it today.
      const input = ProjectionInput(
        grossMonthlySalary: 7000,
        salaryGrowthPercent: 10,
        cpfSalaryCeiling: 7400,
        cpfReturnPercent: 0,
        years: 5,
      );
      final points = project(input);

      expect(points[13].grossSalary, closeTo(7700, 0.01));
      // Contribution in that month is on the ceiling, not the salary.
      final monthly = points[13].contributedToCpf - points[12].contributedToCpf;
      expect(monthly, closeTo(7400 * 0.37, 0.01));
    });

    test('no growth leaves the salary flat', () {
      final points = project(
        const ProjectionInput(grossMonthlySalary: 1000, years: 5),
      );

      expect(points.last.grossSalary, closeTo(1000, 0.01));
    });
  });

  group('ProjectionSummary', () {
    test('separates what was paid in from what was earned', () {
      const input = ProjectionInput(
        startingInvestments: 1000,
        monthlyInvestment: 100,
        investmentReturnPercent: 6,
        cpfReturnPercent: 0,
        years: 10,
      );
      final summary = ProjectionSummary.of(project(input), input);

      expect(summary.totalContributed, closeTo(1000 + 100 * 120, 0.01));
      expect(summary.growth, greaterThan(0));
      expect(
        summary.total,
        closeTo(summary.totalContributed + summary.growth, 0.01),
      );
    });

    test('growth is zero when nothing earns anything', () {
      const input = ProjectionInput(
        startingInvestments: 5000,
        monthlyInvestment: 50,
        investmentReturnPercent: 0,
        cpfReturnPercent: 0,
        years: 3,
      );
      final summary = ProjectionSummary.of(project(input), input);

      expect(summary.growth, closeTo(0, 0.01));
    });
  });
}
