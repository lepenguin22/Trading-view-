/// A discounted-cash-flow fair value for one symbol.
///
/// The DCF is somebody else's model output, not a fact: it is cached with the
/// time it was fetched so the UI can say how old it is, and it is always shown
/// beside the live price rather than in place of it.
class Valuation {
  const Valuation({
    required this.symbol,
    required this.dcf,
    required this.currency,
    required this.fetchedAt,
  });

  final String symbol;

  /// Fair value per share, in [currency].
  final double dcf;

  /// Currency the provider quoted, so a mismatch with the price feed can be
  /// spotted rather than silently compared.
  final String currency;

  /// Epoch ms when this was fetched.
  final int fetchedAt;

  factory Valuation.fromJson(Map<String, dynamic> json) => Valuation(
    symbol: json['symbol'] as String,
    dcf: (json['dcf'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'USD',
    fetchedAt: (json['fetchedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'dcf': dcf,
    'currency': currency,
    'fetchedAt': fetchedAt,
  };
}

/// Where a price sits against a fair value.
///
/// The bands are deliberately wide. A DCF is a projection with wide error
/// bars, and a 3% gap between price and model output is noise — reporting it
/// as "undervalued" would give the number more authority than it has.
enum ValuationVerdict {
  significantlyUndervalued('Significantly undervalued'),
  undervalued('Undervalued'),
  fairlyValued('Fairly valued'),
  overvalued('Overvalued'),
  significantlyOvervalued('Significantly overvalued');

  const ValuationVerdict(this.label);

  final String label;

  bool get isCheap => this == significantlyUndervalued || this == undervalued;
  bool get isExpensive => this == significantlyOvervalued || this == overvalued;
}

/// Price as a fraction of fair value: below 1 is a discount.
double? priceToValue(double price, double dcf) {
  if (!price.isFinite || !dcf.isFinite || dcf <= 0) return null;
  return price / dcf;
}

/// Discount to fair value as a percentage; negative means a premium.
double? marginOfSafety(double price, double dcf) {
  if (!price.isFinite || !dcf.isFinite || dcf <= 0) return null;
  return (dcf - price) / dcf * 100;
}

/// Classifies a price against a fair value.
///
/// Returns null when the DCF is unusable. A non-positive DCF is a real
/// outcome for a company with negative projected cash flows, and calling that
/// "undervalued at any price" would be exactly wrong.
ValuationVerdict? verdictFor(double price, double dcf) {
  final ratio = priceToValue(price, dcf);
  if (ratio == null) return null;

  if (ratio <= 0.70) return ValuationVerdict.significantlyUndervalued;
  if (ratio <= 0.90) return ValuationVerdict.undervalued;
  if (ratio < 1.10) return ValuationVerdict.fairlyValued;
  if (ratio < 1.30) return ValuationVerdict.overvalued;
  return ValuationVerdict.significantlyOvervalued;
}

/// How long a cached DCF is treated as current.
///
/// A DCF moves when the provider re-runs it against new filings — quarterly at
/// most. Refetching more often would spend a rate-limited free tier on a
/// number that has not changed.
const valuationCacheTtl = Duration(days: 7);

bool isStale(Valuation v, {DateTime? now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(v.fetchedAt);
  return (now ?? DateTime.now()).difference(at) > valuationCacheTtl;
}
