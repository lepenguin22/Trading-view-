/// Whether a CPF projection reaches the Basic, Full or Enhanced Retirement Sum.
///
/// Three things make this easy to get wrong, and all three are handled here
/// rather than left to the reader:
///
/// **MediSave does not count.** The Retirement Account is formed at 55 from the
/// Special Account and then the Ordinary Account. MediSave stays where it is,
/// so counting it would clear the bar with money that was never eligible.
///
/// **The comparison happens at 55**, when the Retirement Account is formed —
/// not at the end of a projection that may run well past it.
///
/// **The sums rise with every cohort.** They are fixed for life at the year
/// *you* turn 55, and that year's figure is not today's. Someone turning 55 in
/// 2053 measured against the 2026 Full Retirement Sum would clear it on paper
/// and miss it by half in life.
library;

import 'projection.dart';

/// The published Basic Retirement Sum, and the cohort it belongs to.
///
/// The Full Retirement Sum is twice this and the Enhanced is four times, a
/// relationship CPF sets structurally rather than announcing separately.
const brsBaseYear = 2026;
const brsBaseAmount = 110200.0;

/// The last cohort whose sums have actually been announced.
///
/// Budget 2022 set the 2023-to-2027 cohorts rising about 3.5% a year. Nothing
/// beyond 2027 is published, so every later figure this produces is an
/// extrapolation — which is the single most misleading thing here if it goes
/// unsaid, since anyone under about 50 is projecting into unannounced years.
const lastAnnouncedCohort = 2027;

/// Default annual rise, from the announced 2023-to-2027 schedule.
const brsGrowthPercentDefault = 3.5;

/// The first cohort whose Enhanced Retirement Sum is four times the Basic.
///
/// It was three times until then. Worth encoding rather than assuming a fixed
/// ratio: the multiple is policy that has already moved once, so treating it
/// as arithmetic would quietly misstate every cohort on the other side of the
/// change — and would hide that it can move again.
const ersQuadrupleFrom = 2025;

/// How many times the Basic Retirement Sum the Enhanced is, for [cohortYear].
double ersMultipleFor(int cohortYear) => cohortYear >= ersQuadrupleFrom ? 4 : 3;

/// The three sums for someone turning 55 in [cohortYear].
typedef RetirementSums = ({double brs, double frs, double ers});

RetirementSums retirementSumsFor(
  int cohortYear, {
  double base = brsBaseAmount,
  int baseYear = brsBaseYear,
  double growthPercent = brsGrowthPercentDefault,
}) {
  final years = cohortYear - baseYear;
  var brs = base;
  if (years > 0) {
    for (var i = 0; i < years; i++) {
      brs *= 1 + growthPercent / 100;
    }
  } else if (years < 0) {
    for (var i = 0; i < -years; i++) {
      brs /= 1 + growthPercent / 100;
    }
  }
  // The Full Retirement Sum is twice the Basic, which has held throughout. The
  // Enhanced multiple has not — see [ersMultipleFor].
  return (brs: brs, frs: brs * 2, ers: brs * ersMultipleFor(cohortYear));
}

/// The year someone [age] years old today turns 55.
int cohortYearFor(int age, int thisYear) => thisYear + (55 - age);

/// Whether [cohortYear] is past the last published schedule.
bool isExtrapolated(int cohortYear) => cohortYear > lastAnnouncedCohort;

/// What a projection holds against the retirement sums, measured at 55.
typedef RetirementCheck = ({
  int cohortYear,

  /// Ordinary plus Special at 55 — what forms the Retirement Account.
  double eligible,

  /// MediSave at the same point, carried only so the screen can say it was
  /// left out rather than leaving the reader to wonder.
  double excludedMediSave,
  RetirementSums sums,
});

/// Reads [points] at age 55, or null when the projection cannot answer.
///
/// Null when no age was given, or when the projection stops before 55 — a
/// balance at 40 says nothing about a bar that is measured at 55, and
/// comparing them anyway would be the most flattering possible error.
RetirementCheck? checkRetirementSums(
  List<ProjectionPoint> points,
  ProjectionInput input,
  int thisYear, {
  double base = brsBaseAmount,
  double growthPercent = brsGrowthPercentDefault,
}) {
  final age = input.currentAge;
  if (age <= 0 || age > 55) return null;

  final month = (55 - age) * 12;
  if (month >= points.length) return null;

  final at = points[month];
  return (
    cohortYear: cohortYearFor(age, thisYear),
    eligible: at.oa + at.sa,
    excludedMediSave: at.ma,
    sums: retirementSumsFor(
      cohortYearFor(age, thisYear),
      base: base,
      growthPercent: growthPercent,
    ),
  );
}

/// Where a projection stands against the three sums, as one line.
typedef RetirementStanding = ({
  /// The highest sum cleared, or null when none is.
  String? cleared,

  /// The next one up, or null when the Enhanced sum is already cleared.
  String? next,

  /// What is missing from [next]; zero when there is nothing left to clear.
  double shortfall,
});

/// Reduces a [RetirementCheck] to the highest bar cleared and the next one.
///
/// The card lists all three, but the summary at the top of the screen has room
/// for one line, and "which bar am I over" is the question that line should
/// answer. Without it the verdict lives eight cards down, past four CPF cards,
/// where it reads as absent.
RetirementStanding standingOf(RetirementCheck check) {
  final held = check.eligible;
  final sums = check.sums;

  if (held >= sums.ers) {
    return (cleared: 'Enhanced', next: null, shortfall: 0);
  }
  if (held >= sums.frs) {
    return (cleared: 'Full', next: 'Enhanced', shortfall: sums.ers - held);
  }
  if (held >= sums.brs) {
    return (cleared: 'Basic', next: 'Full', shortfall: sums.frs - held);
  }
  return (cleared: null, next: 'Basic', shortfall: sums.brs - held);
}

/// How many more years a projection needs before it reaches 55.
///
/// Zero when it already does. The default horizon is twenty years, which for
/// anyone under 35 stops short of 55 and leaves the whole retirement question
/// unanswerable — so the number of years missing is worth naming rather than
/// leaving to be worked out.
int yearsShortOf55(int age, int years) {
  if (age <= 0 || age > 55) return 0;
  final needed = 55 - age;
  return years >= needed ? 0 : needed - years;
}
