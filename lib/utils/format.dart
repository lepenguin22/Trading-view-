import 'package:intl/intl.dart';

/// Display formatting helpers. All are pure and safe on non-finite input.

/// Currency codes Yahoo reports in minor units (pence, cents).
const _minorUnitCurrencies = <String, ({String major, double divisor})>{
  'GBp': (major: 'GBP', divisor: 100),
  'ZAc': (major: 'ZAR', divisor: 100),
  'ILA': (major: 'ILS', divisor: 100),
};

/// Formats a price in its quoted currency.
///
/// London tickers quote in pence (`GBp`), which is not an ISO currency code,
/// so those are converted to the major unit first.
String formatPrice(double value, [String currency = 'USD']) {
  if (!value.isFinite) return '—';

  final minor = _minorUnitCurrencies[currency];
  final amount = minor != null ? value / minor.divisor : value;
  final code = minor != null ? minor.major : currency;

  // Sub-unit instruments (penny stocks, some crypto) need more precision than
  // the currency's default two decimals. Exactly zero keeps the plain form.
  final digits = amount != 0 && amount.abs() < 1 ? 4 : 2;

  final symbol = NumberFormat.simpleCurrency(name: code).currencySymbol;
  return NumberFormat.currency(
    symbol: symbol,
    decimalDigits: digits,
  ).format(amount);
}

/// Formats an already-scaled axis value. No currency symbol: the axis repeats
/// its label at every gridline and the currency is in the header, so carrying
/// it here would widen the gutter for no information. [decimals] is chosen for
/// the axis as a whole, so labels line up on the decimal point.
String formatAxisNumber(double displayValue, int decimals) {
  if (!displayValue.isFinite) return '—';
  return NumberFormat.decimalPatternDigits(decimalDigits: decimals)
      .format(displayValue);
}

/// Converts a quoted price into the units the axis labels it in.
///
/// London tickers quote in pence, so an axis drawn in raw quote units would
/// read 7,800 where the header reads £78.00.
double axisScale(double value, String currency) {
  final minor = _minorUnitCurrencies[currency];
  return minor != null ? value / minor.divisor : value;
}

/// Inverse of [axisScale], for placing a label's gridline back on the plot.
double axisUnscale(double displayValue, String currency) {
  final minor = _minorUnitCurrencies[currency];
  return minor != null ? displayValue * minor.divisor : displayValue;
}

/// Formats an absolute change with an explicit sign, e.g. "+2.50".
String formatChange(double value) {
  if (!value.isFinite) return '—';
  final digits = value != 0 && value.abs() < 1 ? 4 : 2;
  return '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(digits)}';
}

/// Formats a percentage with an explicit sign, e.g. "+1.29%".
String formatPercent(double value) {
  if (!value.isFinite) return '—';
  return '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(2)}%';
}

/// "Updated 14:32" style timestamp for the last successful refresh.
String formatUpdatedAt(int? epochMs) {
  if (epochMs == null) return '';
  final time = DateFormat.Hm().format(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  return 'Updated $time';
}

/// Axis/tooltip label for a chart point, scaled to the range being shown.
String formatPointDate(int epochSeconds, bool intraday) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return intraday ? DateFormat.Hm().format(d) : DateFormat.yMMMd().format(d);
}

/// Turns a raw market state into something readable, or '' when unknown.
String describeMarketState(String state) {
  switch (state) {
    case 'REGULAR':
      return 'Market open';
    case 'PRE':
      return 'Pre-market';
    case 'POST':
    case 'POSTPOST':
      return 'After hours';
    case 'CLOSED':
    case 'PREPRE':
      return 'Market closed';
    default:
      return '';
  }
}

/// Normalises user input into the ticker form the feed expects.
String normaliseSymbol(String input) => input.trim().toUpperCase();
