import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/cpf_payout.dart';
import 'package:ticker/utils/projection.dart';
import 'package:ticker/utils/retirement_sums.dart';

void main() {
  group('payoutFor', () {
    test("reproduces CPF's published figures at the Basic and Full sums", () {
      // The two anchors, read back. If either drifts, every payout on the
      // screen drifts with it.
      final brs = payoutFor(110200);
      expect(brs.low, closeTo(860, 0.5));
      expect(brs.high, closeTo(950, 0.5));

      final frs = payoutFor(220400);
      expect(frs.low, closeTo(1670, 0.5));
      expect(frs.high, closeTo(1780, 0.5));
    });

    test('lands on the published Enhanced figure it was not fitted to', () {
      // The line is calibrated on the Basic and Full sums only. That it then
      // hits the published Enhanced range to the dollar is the evidence this
      // is CPF's own arithmetic rather than a curve drawn through it — and
      // the check that would fail first if the anchors were mistyped.
      final ers = payoutFor(440800);
      expect(ers.low, closeTo(3290, 0.5));
      expect(ers.high, closeTo(3440, 0.5));
    });

    test('is not proportional to the balance', () {
      // Doubling the sum must not double the payout. A proportional model
      // would put the Enhanced figure near $3,800 instead of $3,440.
      final frs = payoutFor(220400);
      final ers = payoutFor(440800);
      expect(ers.high, lessThan(frs.high * 2));
      expect(ers.high / 440800, lessThan(frs.high / 220400));
    });

    test('never returns a negative payout', () {
      // A guard, not a case that can arise: a balance is never negative. The
      // line only crosses zero some $6,800 below it, which is why this reaches
      // so far down to exercise the clamp at all.
      expect(payoutFor(-10000).low, 0);
      expect(payoutFor(-20000).high, 0);
    });

    test('the line is nonsense below the published range, and unreachable', () {
      // The line has a positive intercept, so on its own it claims $50 to $120
      // a month for an empty account. That is extrapolation well below
      // anything CPF published, and it is why payoutFor is not the function
      // the screen calls.
      expect(payoutFor(0).high, greaterThan(0));

      // estimatePayout is, and it refuses the whole region: CPF LIFE needs
      // $60,000 at 65, which is about $40,500 at 55, so every balance the
      // nonsense would apply to is answered with no payout at all.
      for (final eligible in [0.0, 1000.0, 20000.0, 40000.0]) {
        expect(
          estimatePayout((
            cohortYear: brsBaseYear,
            eligible: eligible,
            excludedMediSave: 0,
            sums: retirementSumsFor(brsBaseYear),
          )).monthly,
          isNull,
          reason: '\$$eligible at 55 is under the CPF LIFE minimum at 65',
        );
      }
    });
  });

  group('estimatePayout', () {
    /// A check standing at [eligible] for someone turning 55 in [cohortYear].
    RetirementCheck checkAt(double eligible, {int cohortYear = brsBaseYear}) =>
        (
          cohortYear: cohortYear,
          eligible: eligible,
          excludedMediSave: 0,
          sums: retirementSumsFor(cohortYear),
        );

    test('annuitises only up to the Enhanced sum', () {
      final sums = retirementSumsFor(brsBaseYear);
      final estimate = estimatePayout(checkAt(sums.ers + 100000));

      expect(estimate.setAside, closeTo(sums.ers, 0.01));
      expect(estimate.aboveEnhanced, closeTo(100000, 0.01));
      // The payout is the Enhanced one, not the Enhanced one plus a bonus for
      // savings CPF LIFE never sees.
      expect(estimate.monthly!.high, closeTo(3440, 0.5));
    });

    test('nothing is above the Enhanced sum when the balance is under it', () {
      final estimate = estimatePayout(checkAt(220400));
      expect(estimate.aboveEnhanced, 0);
      expect(estimate.setAside, closeTo(220400, 0.01));
    });

    test('payouts begin ten years after the Retirement Account forms', () {
      expect(estimatePayout(checkAt(220400, cohortYear: 2040)).fromYear, 2050);
    });

    test('a balance under the CPF LIFE minimum quotes no payout', () {
      // $30,000 at 55 grows to about $44,400 by 65 — short of the $60,000
      // that puts a member into CPF LIFE automatically. The Retirement Sum
      // Scheme pays out instead, and it is not a lifelong income, so there is
      // nothing here to quote as one.
      final estimate = estimatePayout(checkAt(30000));
      expect(estimate.belowThreshold, isTrue);
      expect(estimate.monthly, isNull);
      expect(
        estimate.atPayoutAge,
        closeTo(
          30000 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04 *
              1.04,
          1,
        ),
      );
    });

    test('a balance just over the minimum does quote one', () {
      // $41,000 at 55 clears $60,000 by 65, where $40,000 does not — the
      // threshold is measured at 65, not at 55, and measuring it at 55 would
      // wrongly deny a payout to both.
      expect(estimatePayout(checkAt(41000)).monthly, isNotNull);
      expect(estimatePayout(checkAt(40000)).monthly, isNull);
    });
  });

  group('a projection end to end', () {
    test('a projection reaching the Full sum quotes the Full payout', () {
      // Balances chosen to land on the 2026 Full sum at 55 with no further
      // contributions, so the payout is the published one rather than an
      // interpolation between anchors.
      const input = ProjectionInput(
        currentAge: 54,
        startingSa: 220400,
        saReturnPercent: 0,
        oaReturnPercent: 0,
        maReturnPercent: 0,
        years: 5,
      );
      final check = checkRetirementSums(project(input), input, brsBaseYear);
      final estimate = estimatePayout(check!);

      expect(check.eligible, closeTo(220400, 0.01));
      expect(estimate.monthly!.low, closeTo(1670, 0.5));
      expect(estimate.monthly!.high, closeTo(1780, 0.5));
    });

    test('MediSave buys no payouts', () {
      // The Retirement Account is formed from Special then Ordinary. A large
      // MediSave balance must not move the payout by a cent.
      const bare = ProjectionInput(
        currentAge: 54,
        startingSa: 220400,
        saReturnPercent: 0,
        oaReturnPercent: 0,
        maReturnPercent: 0,
        years: 5,
      );
      const withMediSave = ProjectionInput(
        currentAge: 54,
        startingSa: 220400,
        startingMa: 500000,
        saReturnPercent: 0,
        oaReturnPercent: 0,
        maReturnPercent: 0,
        years: 5,
      );

      double payout(ProjectionInput input) => estimatePayout(
        checkRetirementSums(project(input), input, brsBaseYear)!,
      ).monthly!.high;

      expect(payout(withMediSave), closeTo(payout(bare), 0.01));
    });
  });
}
