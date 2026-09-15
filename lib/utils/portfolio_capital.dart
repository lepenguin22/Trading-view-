/// Taking the imported portfolio's market value into the calculator.
///
/// The calculator projects CPF alongside investments and adds them into one
/// total, and CPF is Singapore-only — so the whole projection is in one
/// currency, and a portfolio held in another has to be converted before it can
/// join it. Both figures format with a bare "$", so an unconverted USD balance
/// projected as SGD would look entirely correct and be a third light.
library;

import '../models/holding.dart';

/// The portfolio's value in [into], or null when it cannot be stated.
///
/// Null means the rate is missing, not that the portfolio is worth nothing —
/// the caller asks for the rate rather than projecting a figure that is
/// silently in the wrong currency.
double? capitalIn(String into, PortfolioTotal total, double rate) {
  if (!total.value.isFinite || total.value < 0) return null;
  if (total.currency == into) return total.value;
  if (!rate.isFinite || rate <= 0) return null;
  return total.value * rate;
}

/// Whether a conversion is needed to bring [total] into [into].
bool needsConversion(String into, PortfolioTotal total) =>
    total.currency != into;

/// The single currency a portfolio is held in, or null when there is not one.
///
/// Several currencies have no single starting figure, and this app holds no
/// exchange rates of its own to make one — so it says so rather than picking
/// the largest and calling it the portfolio.
PortfolioTotal? soleCurrency(List<PortfolioTotal> totals) =>
    totals.length == 1 ? totals.single : null;
