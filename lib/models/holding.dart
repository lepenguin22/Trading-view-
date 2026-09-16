import '../utils/portfolio_csv.dart' show financialScoreMax, moatScoreMax;
import 'score.dart';

/// Why a scored holding carries no date.
///
/// Three different problems wore the same words once — "no date" was shown
/// whether the sheet had no such column at all or a cell in it could not be
/// read. They are fixed in different places: one is the sheet's layout (or a
/// stale publish that predates the column), the other a single cell's format.
/// Saying which turns a guess into an instruction.
enum NoDateReason {
  /// The sheet had no column saying when scores were arrived at.
  noColumn,

  /// The column is there; this row's cell is empty.
  blank,

  /// The cell held something that could not be read as a date — most often an
  /// order like 03/04/2026, which is refused rather than guessed at.
  unreadable,
}

/// One line of the portfolio: a symbol and, when the sheet says so, how many
/// shares are held.
///
/// [shares] is nullable because a sheet need not have a quantity column, and a
/// holding whose quantity cannot be read is still a holding. Everything that
/// depends on a quantity treats null as "not stated" rather than as zero — a
/// position of unknown size is not a position worth nothing.
class Holding {
  const Holding({
    required this.symbol,
    this.shares,
    this.costPerShare,
    this.financialScore,
    this.moatScore,
    this.scoredAt,
    this.noDateReason,
  });

  final String symbol;

  /// Share count from the sheet. May be fractional, and may be negative for a
  /// short position.
  final double? shares;

  /// Average price paid per share, when the sheet has a cost column.
  ///
  /// Per share rather than per position: a sheet's total-cost column is a
  /// different number, and treating one as the other would be wrong by a
  /// factor of the share count.
  final double? costPerShare;

  /// Financial checklist score from the analysis framework, when the sheet
  /// carries one — with the scale it was marked out of, since criteria that do
  /// not apply to a company are dropped rather than scored zero.
  ///
  /// Recorded, never computed: the criteria need multi-year statements and
  /// peer benchmarking that no price feed provides, and several are outright
  /// qualitative. The app's job is to carry a judgement already made.
  final Score? financialScore;

  /// Moat score, on the same terms.
  final Score? moatScore;

  /// When those scores were arrived at.
  ///
  /// Shown beside them because a score is a snapshot: one from six months ago
  /// may predate two earnings reports, and a stale judgement presented as
  /// current is the way this feature would mislead.
  final DateTime? scoredAt;

  /// Why [scoredAt] is absent. Null whenever a date was read, and null on a
  /// holding from a build that predates this, where the reason is unknowable
  /// rather than any particular one of the three.
  final NoDateReason? noDateReason;

  /// True when either score exists.
  bool get hasScores => financialScore != null || moatScore != null;

  /// Market value at [price], or null when the quantity is not known.
  double? valueAt(double price) {
    final count = shares;
    if (count == null || !price.isFinite) return null;
    return count * price;
  }

  /// What the position cost, or null when either half is unknown.
  double? get costBasis {
    final count = shares;
    final cost = costPerShare;
    if (count == null || cost == null) return null;
    return count * cost;
  }

  /// Gain since purchase at [price], or null when the cost is not known.
  double? gainAt(double price) {
    final value = valueAt(price);
    final cost = costBasis;
    if (value == null || cost == null) return null;
    return value - cost;
  }

  Holding copyWith({
    String? symbol,
    double? shares,
    double? costPerShare,
    Score? financialScore,
    Score? moatScore,
    DateTime? scoredAt,
    NoDateReason? noDateReason,
  }) => Holding(
    symbol: symbol ?? this.symbol,
    shares: shares ?? this.shares,
    costPerShare: costPerShare ?? this.costPerShare,
    financialScore: financialScore ?? this.financialScore,
    moatScore: moatScore ?? this.moatScore,
    scoredAt: scoredAt ?? this.scoredAt,
    noDateReason: noDateReason ?? this.noDateReason,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    if (shares != null) 'shares': shares,
    if (costPerShare != null) 'costPerShare': costPerShare,
    if (financialScore != null) 'financialScore': financialScore!.toJson(),
    if (moatScore != null) 'moatScore': moatScore!.toJson(),
    if (scoredAt != null) 'scoredAt': scoredAt!.millisecondsSinceEpoch,
    if (noDateReason != null) 'noDateReason': noDateReason!.name,
  };

  static Holding? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final symbol = raw['symbol'];
    if (symbol is! String || symbol.isEmpty) return null;
    final shares = raw['shares'];
    final cost = raw['costPerShare'];
    final scoredAt = raw['scoredAt'];
    return Holding(
      symbol: symbol,
      shares: shares is num && shares.isFinite ? shares.toDouble() : null,
      costPerShare: cost is num && cost.isFinite && cost > 0
          ? cost.toDouble()
          : null,
      // Bounds are re-checked on load, not just on parse, and a bare number
      // written by a build from before scales were carried still reads —
      // against the framework's scale, which is what that build assumed.
      financialScore: Score.fromJson(raw['financialScore'], financialScoreMax),
      moatScore: Score.fromJson(raw['moatScore'], moatScoreMax),
      scoredAt: scoredAt is num && scoredAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(scoredAt.toInt())
          : null,
      noDateReason: _reasonFrom(raw['noDateReason']),
    );
  }

  /// Reads a stored reason, ignoring one this build does not know.
  ///
  /// A name written by a later build is dropped rather than guessed at: an
  /// unknown reason is no reason, which is exactly what null already means.
  static NoDateReason? _reasonFrom(Object? raw) {
    if (raw is! String) return null;
    for (final reason in NoDateReason.values) {
      if (reason.name == raw) return reason;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Holding &&
      other.symbol == symbol &&
      other.shares == shares &&
      other.costPerShare == costPerShare &&
      other.financialScore == financialScore &&
      other.moatScore == moatScore &&
      other.scoredAt == scoredAt &&
      other.noDateReason == noDateReason;

  @override
  int get hashCode => Object.hash(
    symbol,
    shares,
    costPerShare,
    financialScore,
    moatScore,
    scoredAt,
    noDateReason,
  );

  @override
  String toString() =>
      'Holding($symbol, shares: $shares, costPerShare: $costPerShare, '
      'financialScore: $financialScore, moatScore: $moatScore)';
}

/// A portfolio's worth in one currency.
///
/// Totals are kept per currency and never summed across them: adding dollars
/// to pounds needs an exchange rate this app does not have, and a single
/// made-up number would be worse than two honest ones.
class PortfolioTotal {
  const PortfolioTotal({
    required this.currency,
    required this.value,
    required this.dayChange,
    required this.priced,
    required this.unpriced,
    this.cost = 0,
    this.gain = 0,
    this.invested = 0,
  });

  final String currency;

  /// Market value of every holding that could be valued.
  final double value;

  /// Change in [value] since the previous close.
  final double dayChange;

  /// How many holdings contributed.
  final int priced;

  /// Holdings left out, because no quantity was known or no quote had arrived.
  /// Surfaced so a total is never quietly short of a position.
  final int unpriced;

  /// What the holdings that have a cost basis were bought for.
  final double cost;

  /// [value] less [cost], over those same holdings only.
  final double gain;

  /// How many holdings had a cost basis and so contributed to [gain].
  ///
  /// Compared against [priced] by the UI: a gain measured over fewer holdings
  /// than the value beside it must say so, or it reads as the whole
  /// portfolio's return when it is not.
  final int invested;

  /// True when every valued holding also had a cost, so the gain covers the
  /// same positions the value does.
  bool get gainCoversEverything => invested == priced;

  /// Whether a gain can be shown at all.
  bool get hasGain => invested > 0 && cost != 0;

  /// Gain as a percentage of what was paid.
  double? get gainPercent {
    if (!hasGain || !cost.isFinite || cost == 0) return null;
    return gain / cost * 100;
  }

  /// Day change as a percentage of where the holdings opened.
  double? get dayChangePercent {
    final opening = value - dayChange;
    if (opening == 0 || !opening.isFinite) return null;
    return dayChange / opening * 100;
  }
}
