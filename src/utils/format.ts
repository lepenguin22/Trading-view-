/** Display formatting helpers. All are pure and safe on non-finite input. */

/** Currency codes Yahoo reports in minor units (pence, cents). */
const MINOR_UNIT_CURRENCIES: Record<string, { major: string; divisor: number }> = {
  GBp: { major: 'GBP', divisor: 100 },
  ZAc: { major: 'ZAR', divisor: 100 },
  ILA: { major: 'ILS', divisor: 100 },
};

/**
 * Formats a price in its quoted currency.
 *
 * London tickers quote in pence (`GBp`), which Intl does not recognise as a
 * currency code, so those are converted to the major unit first.
 */
export function formatPrice(value: number, currency = 'USD'): string {
  if (!Number.isFinite(value)) return '—';

  const minor = MINOR_UNIT_CURRENCIES[currency];
  const amount = minor ? value / minor.divisor : value;
  const code = minor ? minor.major : currency;

  // Sub-unit instruments (penny stocks, some crypto) need more precision than
  // the currency's default two decimals. Exactly zero keeps the plain form.
  const digits = amount !== 0 && Math.abs(amount) < 1 ? 4 : 2;

  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency: code,
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    }).format(amount);
  } catch {
    // Intl renders unknown-but-well-formed codes as "XYZ 10.00" on its own and
    // only throws (RangeError) on a malformed one, which is the case here.
    return `${amount.toFixed(digits)} ${code}`;
  }
}

/** Formats an absolute change with an explicit sign, e.g. "+2.50". */
export function formatChange(value: number): string {
  if (!Number.isFinite(value)) return '—';
  const digits = value !== 0 && Math.abs(value) < 1 ? 4 : 2;
  return `${value >= 0 ? '+' : '−'}${Math.abs(value).toFixed(digits)}`;
}

/** Formats a percentage with an explicit sign, e.g. "+1.29%". */
export function formatPercent(value: number): string {
  if (!Number.isFinite(value)) return '—';
  return `${value >= 0 ? '+' : '−'}${Math.abs(value).toFixed(2)}%`;
}

/** "Updated 14:32" style timestamp for the last successful refresh. */
export function formatUpdatedAt(epochMs: number | null): string {
  if (epochMs === null) return '';
  try {
    const time = new Date(epochMs).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
    return `Updated ${time}`;
  } catch {
    return '';
  }
}

/** Axis/tooltip label for a chart point, scaled to the range being shown. */
export function formatPointDate(epochSeconds: number, intraday: boolean): string {
  const d = new Date(epochSeconds * 1000);
  return intraday
    ? d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: '2-digit' });
}

/** Turns a raw market state into something readable, or '' when unknown. */
export function describeMarketState(state: string): string {
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

/** Normalises user input into the ticker form the feed expects. */
export function normaliseSymbol(input: string): string {
  return input.trim().toUpperCase();
}
