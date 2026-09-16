/// What CPF LIFE pays monthly, from the Retirement Account formed at 55.
///
/// Four things make this easy to overstate, and all four are handled here:
///
/// **Payouts start at 65, not 55.** The Retirement Account is formed at 55 and
/// then sits for ten years earning interest before a cent is paid out. The
/// figures below are CPF's own, expressed as "set aside this at 55, receive
/// this from 65", so that decade is already inside them.
///
/// **The payout is not proportional to the balance.** Twice the Retirement
/// Account is not twice the payout: CPF's published figures work out at $8.62
/// a month per $1,000 at the Basic sum and $7.80 at the Enhanced. Scaling a
/// single ratio would overstate a large balance by about a hundred dollars a
/// month.
///
/// **Only what reaches the Enhanced sum is annuitised.** Eligible savings above
/// it stay in the Ordinary and Special Accounts. They are still yours — they
/// are simply not buying payouts, and counting them would inflate the figure
/// without limit.
///
/// **Below $60,000 there is no annuity at all.** CPF LIFE includes a member
/// automatically only from that much in the Retirement Account at 65. Under it
/// the Retirement Sum Scheme pays out until the savings are gone, which is not
/// the lifelong income the word "payout" implies.
library;

import 'retirement_sums.dart';

/// CPF's published Standard Plan figures for the [brsBaseYear] cohort: set
/// this much aside at 55, receive this much monthly from 65.
///
/// Two points rather than three because these two are the ones every source
/// agrees on. The line they define reproduces the published Enhanced figure —
/// \$3,290 to \$3,440 on a \$440,800 sum — to the dollar, which is the check
/// that this is CPF's own arithmetic rather than a curve fitted to it.
///
/// A range, not a figure, because CPF publishes a range: payouts differ
/// between members on the same sum, and quoting only the top of it — which is
/// the number most articles carry — would flatter every projection here.
const cpfLifeLowerAnchors = <({double sum, double monthly})>[
  (sum: 110200, monthly: 860),
  (sum: 220400, monthly: 1670),
];
const cpfLifeUpperAnchors = <({double sum, double monthly})>[
  (sum: 110200, monthly: 950),
  (sum: 220400, monthly: 1780),
];

/// The Retirement Account needed at 65 to be included in CPF LIFE.
const cpfLifeThresholdAtPayout = 60000.0;

/// The age the Retirement Account is formed, and the age payouts begin.
const retirementAccountAge = 55;
const payoutAge = 65;

/// What the Retirement Account earns between 55 and 65.
///
/// Only used to carry the balance to the age the [cpfLifeThresholdAtPayout] is
/// measured at. The payouts themselves need no rate — CPF's figures are keyed
/// on the balance at 55 and already contain this decade of interest.
const retirementAccountReturnPercent = 4.0;

/// A monthly payout, as the range CPF publishes rather than a single figure.
typedef PayoutRange = ({double low, double high});

/// The monthly payout for [setAside] at 55, on the line through [anchors].
double _onLine(double setAside, List<({double sum, double monthly})> anchors) {
  final first = anchors.first;
  final last = anchors.last;
  final slope = (last.monthly - first.monthly) / (last.sum - first.sum);
  final payout = first.monthly + (setAside - first.sum) * slope;
  return payout < 0 ? 0 : payout;
}

/// The monthly payout from 65 for [setAside] in the Retirement Account at 55.
PayoutRange payoutFor(double setAside) => (
  low: _onLine(setAside, cpfLifeLowerAnchors),
  high: _onLine(setAside, cpfLifeUpperAnchors),
);

/// What a projection buys in retirement income.
typedef PayoutEstimate = ({
  /// What is annuitised: eligible savings at 55, capped at the Enhanced sum.
  double setAside,

  /// Eligible savings above the Enhanced sum. Still yours, simply not buying
  /// payouts — named so the difference is visible rather than silently lost.
  double aboveEnhanced,

  /// [setAside] carried to [payoutAge], where the threshold is measured.
  double atPayoutAge,

  /// True when that balance is under [cpfLifeThresholdAtPayout], so CPF LIFE
  /// would not include the member automatically and there is no lifelong
  /// payout to quote.
  bool belowThreshold,

  /// The monthly payout from [payoutAge]. Null when [belowThreshold].
  PayoutRange? monthly,

  /// The calendar year payouts would begin.
  int fromYear,
});

/// What [check] works out to in monthly payouts.
///
/// Always answers, because [check] is itself null when the projection cannot
/// reach 55 — by the time there is a Retirement Account to read, there is a
/// payout to quote. What can still be absent is the payout itself, when the
/// balance falls under [cpfLifeThresholdAtPayout]; that is a null [monthly],
/// not a zero, because "\$0 a month" would read as an answer rather than as a
/// different scheme paying out on different terms.
PayoutEstimate estimatePayout(RetirementCheck check) {
  final ers = check.sums.ers;
  final setAside = check.eligible > ers ? ers : check.eligible;
  final aboveEnhanced = check.eligible > ers ? check.eligible - ers : 0.0;

  var atPayoutAge = setAside;
  for (var i = 0; i < payoutAge - retirementAccountAge; i++) {
    atPayoutAge *= 1 + retirementAccountReturnPercent / 100;
  }

  final belowThreshold = atPayoutAge < cpfLifeThresholdAtPayout;
  return (
    setAside: setAside,
    aboveEnhanced: aboveEnhanced,
    atPayoutAge: atPayoutAge,
    belowThreshold: belowThreshold,
    monthly: belowThreshold ? null : payoutFor(setAside),
    fromYear: check.cohortYear + (payoutAge - retirementAccountAge),
  );
}
