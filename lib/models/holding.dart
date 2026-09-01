/// One line of the portfolio: a symbol and, when the sheet says so, how many
/// shares are held.
///
/// [shares] is nullable because a sheet need not have a quantity column, and a
/// holding whose quantity cannot be read is still a holding. Everything that
/// depends on a quantity treats null as "not stated" rather than as zero — a
/// position of unknown size is not a position worth nothing.
class Holding {
  const Holding({required this.symbol, this.shares});

  final String symbol;

  /// Share count from the sheet. May be fractional, and may be negative for a
  /// short position.
  final double? shares;

  /// Market value at [price], or null when the quantity is not known.
  double? valueAt(double price) {
    final count = shares;
    if (count == null || !price.isFinite) return null;
    return count * price;
  }

  Holding copyWith({String? symbol, double? shares}) =>
      Holding(symbol: symbol ?? this.symbol, shares: shares ?? this.shares);

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    if (shares != null) 'shares': shares,
  };

  static Holding? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final symbol = raw['symbol'];
    if (symbol is! String || symbol.isEmpty) return null;
    final shares = raw['shares'];
    return Holding(
      symbol: symbol,
      shares: shares is num && shares.isFinite ? shares.toDouble() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Holding && other.symbol == symbol && other.shares == shares;

  @override
  int get hashCode => Object.hash(symbol, shares);

  @override
  String toString() => 'Holding($symbol, shares: $shares)';
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

  /// Day change as a percentage of where the holdings opened.
  double? get dayChangePercent {
    final opening = value - dayChange;
    if (opening == 0 || !opening.isFinite) return null;
    return dayChange / opening * 100;
  }
}
