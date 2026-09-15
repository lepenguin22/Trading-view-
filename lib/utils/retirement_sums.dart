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

/// Default annual rise, from the announced 2023-2027 schedule.
const brsGrowthPercentDefault = 3.5;

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
  // Structural, not separately announced: the Full Retirement Sum is twice the
  // Basic, and the Enhanced is four times it.
  return (brs: brs, frs: brs * 2, ers: brs * 4);
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
