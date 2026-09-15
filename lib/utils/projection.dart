/// Compound growth of savings and CPF, projected month by month.
///
/// Nothing here encodes CPF policy. Contribution rates, the wage ceiling and
/// the interest rate are all inputs, because every one of them has changed in
/// recent years and a calculator quietly using a stale figure is worse than
/// one that asks. What this does is the arithmetic.
library;

import 'cpf_allocation.dart';

/// One month of a projection.
class ProjectionPoint {
  const ProjectionPoint({
    required this.month,
    required this.grossSalary,
    required this.takeHome,
    required this.invested,
    required this.oa,
    required this.sa,
    required this.ma,
    required this.contributedToInvestments,
    required this.contributedToCpf,
  });

  /// Months elapsed; 0 is the starting position, before any contribution.
  final int month;

  /// Monthly gross pay at this point, after any growth applied so far.
  final double grossSalary;

  /// Gross less the employee's CPF share.
  final double takeHome;

  /// Investment balance at the end of this month.
  final double invested;

  /// Ordinary Account balance at the end of this month.
  final double oa;

  /// Special Account balance.
  final double sa;

  /// MediSave balance.
  final double ma;

  /// The three CPF accounts together.
  double get cpf => oa + sa + ma;

  /// Cumulative amount paid into investments, excluding growth.
  final double contributedToInvestments;

  /// Cumulative amount paid into CPF, excluding interest.
  final double contributedToCpf;

  double get total => invested + cpf;
}

/// What a projection was asked for.
class ProjectionInput {
  const ProjectionInput({
    this.grossMonthlySalary = 0,
    this.employeeCpfPercent = 20,
    this.cpfSalaryCeiling,
    this.monthlyInvestment = 0,
    this.monthlyExpenses = 0,
    this.startingInvestments = 0,
    this.startingOa = 0,
    this.startingSa = 0,
    this.startingMa = 0,
    this.currentAge = 0,
    this.oaPercent = 23,
    this.saPercent = 6,
    this.maPercent = 8,
    this.investmentReturnPercent = 7,
    this.oaReturnPercent = 2.5,
    this.saReturnPercent = 4,
    this.maReturnPercent = 4,
    this.salaryGrowthPercent = 0,
    this.years = 20,
  });

  final double grossMonthlySalary;

  /// The employee's share, deducted from gross to give take-home.
  final double employeeCpfPercent;

  /// Monthly wage above which no CPF is contributed, or null for no ceiling.
  ///
  /// Optional because it is policy that moves. It matters over a long
  /// projection even for a salary below it today: growth carries a salary
  /// through the ceiling, and ignoring that overstates CPF for every year
  /// after.
  final double? cpfSalaryCeiling;

  final double monthlyInvestment;

  /// Average monthly spending, out of take-home pay.
  ///
  /// It does not drive the projection — how much is invested is an input, not
  /// something derived from what is left — but without it "left after
  /// investing" was take-home minus the investment alone, which on any real
  /// budget is a number nobody has.
  final double monthlyExpenses;

  final double startingInvestments;

  /// Opening balances, per account.
  final double startingOa;
  final double startingSa;
  final double startingMa;

  /// Age today, or 0 when it was not given.
  ///
  /// When set, it decides the allocation instead of the three percentages
  /// below, and keeps deciding it as the projection runs: someone 34 today
  /// spends part of a twenty-year projection in each of three bands, and
  /// holding their first band for all twenty years would overstate the
  /// Ordinary Account for most of it.
  final int currentAge;

  /// Where each month's CPF lands, as a percentage of the wage — the form
  /// CPF publishes its allocation tables in, so a rate looked up there can be
  /// typed in as written.
  ///
  /// Used only when [currentAge] is 0. Leaving the age blank is how someone
  /// with an arrangement the table does not describe keeps control of it.
  ///
  /// These three decide the contribution; [employeeCpfPercent] only decides
  /// how much of it comes out of take-home pay. The rest is the employer's,
  /// which is why [employerShareOfWagePercent] is derived rather than asked
  /// for — two inputs that had to agree would be a rule to get wrong.
  final double oaPercent;
  final double saPercent;
  final double maPercent;

  /// The split in force at [month] of the projection.
  ///
  /// Whole years: a band changes on a birthday, and a projection that models
  /// the month CPF actually switches would be claiming a precision the rest of
  /// this does not have.
  CpfAllocation allocationAt(int month) {
    if (currentAge <= 0) {
      return (oa: oaPercent, sa: saPercent, ma: maPercent);
    }
    return cpfAllocationFor(currentAge + month ~/ 12);
  }

  /// True when the projection reaches an age the allocation table stops at.
  bool get outgrowsAllocationTable =>
      projectionPassesCoveredAges(currentAge, years);

  /// Annual nominal returns, compounded monthly.
  final double investmentReturnPercent;

  /// Per account, because they do not pay the same: the Ordinary Account
  /// earns less than Special and MediSave, and averaging them into one rate
  /// was the thing this split exists to stop.
  final double oaReturnPercent;
  final double saReturnPercent;
  final double maReturnPercent;

  /// Annual pay rise, applied once every twelve months.
  final double salaryGrowthPercent;

  final int years;

  /// Gross less the employee's CPF share, at today's salary.
  double get takeHome =>
      grossMonthlySalary - grossMonthlySalary * _fraction(employeeCpfPercent);

  /// What is left of take-home once spending is out, before investing.
  double get afterExpenses => takeHome - monthlyExpenses;

  /// What is left once both spending and the monthly investment are out.
  double get remainingAfterInvesting =>
      takeHome - monthlyExpenses - monthlyInvestment;

  /// True when spending and investing together come to more than take-home.
  ///
  /// The projection still runs — a month can be covered from savings, and
  /// refusing to project would be less useful than saying so — but a plan that
  /// needs more than the pay it is built on should not look affordable.
  bool get outgoingsExceedTakeHome =>
      grossMonthlySalary > 0 && monthlyExpenses + monthlyInvestment > takeHome;

  /// Everything reaching CPF each month, as a percentage of the wage, at the
  /// start of the projection.
  double get cpfPercent {
    final a = allocationAt(0);
    return a.oa + a.sa + a.ma;
  }

  /// The employer's share, as a percentage of the wage.
  ///
  /// Derived: what lands in CPF that did not come out of take-home pay.
  double get employerShareOfWagePercent => cpfPercent - employeeCpfPercent;

  /// True when more is taken from pay than reaches CPF, which cannot happen.
  ///
  /// It means the allocation and the employee rate disagree — most likely one
  /// of them was typed for a different age band — and every CPF figure below
  /// would be built on it.
  bool get employeeRateExceedsCpf =>
      grossMonthlySalary > 0 && employeeCpfPercent > cpfPercent;
}

double _fraction(double percent) => percent / 100;

/// Projects both pots month by month, oldest first.
///
/// Contributions land at the end of each month and interest is credited
/// monthly on the balance before that month's contribution — the ordinary
/// annuity convention. It understates slightly against a bank crediting daily,
/// which is the direction to err in for a projection.
///
/// The returned list always starts with the opening position at month 0, so a
/// chart has a point to begin from even for a zero-year projection.
List<ProjectionPoint> project(ProjectionInput input) {
  final months = input.years * 12;
  var salary = input.grossMonthlySalary;
  var invested = input.startingInvestments;
  var oa = input.startingOa;
  var sa = input.startingSa;
  var ma = input.startingMa;
  var paidIn = 0.0;
  var paidToCpf = 0.0;

  final monthlyInvestmentRate = _fraction(input.investmentReturnPercent) / 12;
  final monthlyOaRate = _fraction(input.oaReturnPercent) / 12;
  final monthlySaRate = _fraction(input.saReturnPercent) / 12;
  final monthlyMaRate = _fraction(input.maReturnPercent) / 12;

  final out = <ProjectionPoint>[
    ProjectionPoint(
      month: 0,
      grossSalary: salary,
      takeHome: salary - salary * _fraction(input.employeeCpfPercent),
      invested: invested,
      oa: oa,
      sa: sa,
      ma: ma,
      contributedToInvestments: 0,
      contributedToCpf: 0,
    ),
  ];
  if (months <= 0) return out;

  for (var month = 1; month <= months; month++) {
    // A pay rise lands at the start of each year after the first.
    if (month > 1 && (month - 1) % 12 == 0) {
      salary *= 1 + _fraction(input.salaryGrowthPercent);
    }

    final eligible = input.cpfSalaryCeiling == null
        ? salary
        : (salary < input.cpfSalaryCeiling! ? salary : input.cpfSalaryCeiling!);
    // Each account takes its own share of the wage, so the split is exact
    // rather than a proportion of a rounded total. Read per month, because an
    // age-driven split changes underneath the projection as it runs.
    final share = input.allocationAt(month - 1);
    final toOa = eligible * _fraction(share.oa);
    final toSa = eligible * _fraction(share.sa);
    final toMa = eligible * _fraction(share.ma);

    invested = invested * (1 + monthlyInvestmentRate) + input.monthlyInvestment;
    oa = oa * (1 + monthlyOaRate) + toOa;
    sa = sa * (1 + monthlySaRate) + toSa;
    ma = ma * (1 + monthlyMaRate) + toMa;
    paidIn += input.monthlyInvestment;
    paidToCpf += toOa + toSa + toMa;

    out.add(
      ProjectionPoint(
        month: month,
        grossSalary: salary,
        takeHome: salary - salary * _fraction(input.employeeCpfPercent),
        invested: invested,
        oa: oa,
        sa: sa,
        ma: ma,
        contributedToInvestments: paidIn,
        contributedToCpf: paidToCpf,
      ),
    );
  }

  return out;
}

/// The end of a projection, summarised.
class ProjectionSummary {
  const ProjectionSummary({
    required this.invested,
    required this.oa,
    required this.sa,
    required this.ma,
    required this.contributedToInvestments,
    required this.contributedToCpf,
    required this.startingCapital,
  });

  factory ProjectionSummary.of(
    List<ProjectionPoint> points,
    ProjectionInput input,
  ) {
    final last = points.last;
    return ProjectionSummary(
      invested: last.invested,
      oa: last.oa,
      sa: last.sa,
      ma: last.ma,
      contributedToInvestments: last.contributedToInvestments,
      contributedToCpf: last.contributedToCpf,
      startingCapital:
          input.startingInvestments +
          input.startingOa +
          input.startingSa +
          input.startingMa,
    );
  }

  final double invested;
  final double oa;
  final double sa;
  final double ma;

  /// The three accounts together.
  double get cpf => oa + sa + ma;

  final double contributedToInvestments;
  final double contributedToCpf;
  final double startingCapital;

  double get total => invested + cpf;

  /// Everything paid in, including what was there at the start.
  double get totalContributed =>
      startingCapital + contributedToInvestments + contributedToCpf;

  /// The part of the total that is growth rather than contribution.
  ///
  /// Reported separately because it is the whole point of the exercise: a
  /// projection that only showed a final number would not say how much of it
  /// was earned rather than saved.
  double get growth => total - totalContributed;
}
