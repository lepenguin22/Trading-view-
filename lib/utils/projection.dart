/// Compound growth of savings and CPF, projected month by month.
///
/// Nothing here encodes CPF policy. Contribution rates, the wage ceiling and
/// the interest rate are all inputs, because every one of them has changed in
/// recent years and a calculator quietly using a stale figure is worse than
/// one that asks. What this does is the arithmetic.
library;

/// One month of a projection.
class ProjectionPoint {
  const ProjectionPoint({
    required this.month,
    required this.grossSalary,
    required this.takeHome,
    required this.invested,
    required this.cpf,
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

  /// CPF balance at the end of this month.
  final double cpf;

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
    this.employerCpfPercent = 17,
    this.cpfSalaryCeiling,
    this.monthlyInvestment = 0,
    this.startingInvestments = 0,
    this.startingCpf = 0,
    this.investmentReturnPercent = 7,
    this.cpfReturnPercent = 2.5,
    this.salaryGrowthPercent = 0,
    this.years = 20,
  });

  final double grossMonthlySalary;

  /// The employee's share, deducted from gross to give take-home.
  final double employeeCpfPercent;

  /// The employer's share, which reaches CPF without passing through pay.
  final double employerCpfPercent;

  /// Monthly wage above which no CPF is contributed, or null for no ceiling.
  ///
  /// Optional because it is policy that moves. It matters over a long
  /// projection even for a salary below it today: growth carries a salary
  /// through the ceiling, and ignoring that overstates CPF for every year
  /// after.
  final double? cpfSalaryCeiling;

  final double monthlyInvestment;
  final double startingInvestments;
  final double startingCpf;

  /// Annual nominal returns, compounded monthly.
  final double investmentReturnPercent;
  final double cpfReturnPercent;

  /// Annual pay rise, applied once every twelve months.
  final double salaryGrowthPercent;

  final int years;

  /// Gross less the employee's CPF share, at today's salary.
  double get takeHome =>
      grossMonthlySalary - grossMonthlySalary * _fraction(employeeCpfPercent);

  /// What is left of take-home after the monthly investment.
  double get remainingAfterInvesting => takeHome - monthlyInvestment;

  /// True when the plan invests more than take-home pay allows.
  bool get investsBeyondTakeHome =>
      grossMonthlySalary > 0 && monthlyInvestment > takeHome;
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
  var cpf = input.startingCpf;
  var paidIn = 0.0;
  var paidToCpf = 0.0;

  final monthlyInvestmentRate = _fraction(input.investmentReturnPercent) / 12;
  final monthlyCpfRate = _fraction(input.cpfReturnPercent) / 12;
  final cpfRate = _fraction(
    input.employeeCpfPercent + input.employerCpfPercent,
  );

  final out = <ProjectionPoint>[
    ProjectionPoint(
      month: 0,
      grossSalary: salary,
      takeHome: salary - salary * _fraction(input.employeeCpfPercent),
      invested: invested,
      cpf: cpf,
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
    final cpfContribution = eligible * cpfRate;

    invested = invested * (1 + monthlyInvestmentRate) + input.monthlyInvestment;
    cpf = cpf * (1 + monthlyCpfRate) + cpfContribution;
    paidIn += input.monthlyInvestment;
    paidToCpf += cpfContribution;

    out.add(
      ProjectionPoint(
        month: month,
        grossSalary: salary,
        takeHome: salary - salary * _fraction(input.employeeCpfPercent),
        invested: invested,
        cpf: cpf,
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
    required this.cpf,
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
      cpf: last.cpf,
      contributedToInvestments: last.contributedToInvestments,
      contributedToCpf: last.contributedToCpf,
      startingCapital: input.startingInvestments + input.startingCpf,
    );
  }

  final double invested;
  final double cpf;
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
