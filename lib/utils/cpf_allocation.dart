/// How a CPF contribution is split between the three accounts, by age.
///
/// This is the one piece of CPF policy the app carries a number for, and it is
/// carried reluctantly: allocation moves, and a calculator quietly using a
/// stale table is worse than one that asks. Three things keep that honest —
/// the table states when it was taken and from where, the shares it produces
/// are shown rather than hidden, and leaving the age blank goes back to typing
/// them in by hand.
///
/// Figures are percentages **of wage**, the form CPF publishes allocation in,
/// for private-sector employees earning above $750 a month. Effective
/// 1 January 2026.
///
/// Cross-checked two ways: against the published allocation *ratios* (the
/// share of the contribution rather than of the wage), which reproduce these
/// exactly at a 37% total — 0.5677 × 37 = 21.0, 0.4055 × 37 = 15.0,
/// 0.3108 × 37 = 11.5, 0.2837 × 37 = 10.5.
///
/// See README, "Allocation by age", for the sources and how to check them.
library;

/// The oldest age this table covers.
///
/// Past 55 the model this app uses stops describing CPF at all: the Special
/// Account closes and contributions go to a Retirement Account up to the Full
/// Retirement Sum, and the total contribution rate falls away from 37%.
/// Neither is modelled here, so the table stops rather than inventing a band.
const cpfAllocationCoveredTo = 55;

/// One age band's split, as percentages of wage.
typedef CpfAllocation = ({double oa, double sa, double ma});

/// The split for someone [age] years old.
///
/// Bands are inclusive of their upper age: CPF's "35 & below" covers 35, and
/// "above 35 to 45" starts at 36.
///
/// Returns the 50-to-55 band for anyone older, which is an approximation and
/// is why [projectionPassesCoveredAges] exists to say so out loud.
CpfAllocation cpfAllocationFor(int age) {
  if (age <= 35) return (oa: 23, sa: 6, ma: 8);
  if (age <= 45) return (oa: 21, sa: 7, ma: 9);
  if (age <= 50) return (oa: 19, sa: 8, ma: 10);
  return (oa: 15, sa: 11.5, ma: 10.5);
}

/// A label for the band [age] falls in, for showing which one is in effect.
String cpfBandLabel(int age) {
  if (age <= 35) return '35 and below';
  if (age <= 45) return 'above 35 to 45';
  if (age <= 50) return 'above 45 to 50';
  if (age <= 55) return 'above 50 to 55';
  return 'above 55 — beyond what this models';
}

/// Whether a projection from [age] running [years] reaches an age the table
/// does not cover.
bool projectionPassesCoveredAges(int age, int years) =>
    age > 0 && age + years > cpfAllocationCoveredTo;
