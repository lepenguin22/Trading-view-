import {
  describeMarketState,
  formatChange,
  formatPercent,
  formatPrice,
  formatUpdatedAt,
  normaliseSymbol,
} from '../utils/format';

describe('formatPrice', () => {
  it('formats a normal price to two decimals', () => {
    // Locale decides the symbol's placement, so assert on the digits only.
    expect(formatPrice(196.5, 'USD')).toContain('196.50');
  });

  it('converts pence-quoted London tickers to pounds', () => {
    // GBp is not a currency code Intl accepts, and 78.4 pence is £0.78.
    const out = formatPrice(78.4, 'GBp');
    expect(out).toContain('0.78');
    expect(out).not.toContain('78.40');
  });

  it('shows four decimals for sub-unit prices', () => {
    expect(formatPrice(0.0432, 'USD')).toContain('0.0432');
  });

  it('renders an unrecognised but well-formed currency code alongside the number', () => {
    // Intl does not throw for these, it just uses the code as the symbol.
    expect(formatPrice(10, 'XYZ')).toContain('10.00');
    expect(formatPrice(10, 'XYZ')).toContain('XYZ');
  });

  it('falls back to a plain number when the currency code is malformed', () => {
    // Anything that is not three letters makes Intl throw a RangeError.
    expect(formatPrice(10, 'NOT_A_CODE')).toBe('10.00 NOT_A_CODE');
  });

  it('renders a dash rather than NaN', () => {
    expect(formatPrice(NaN)).toBe('—');
    expect(formatPrice(Infinity)).toBe('—');
  });
});

describe('formatChange and formatPercent', () => {
  it('always carries an explicit sign', () => {
    expect(formatChange(2.5)).toBe('+2.50');
    expect(formatChange(-2.5)).toBe('−2.50');
    expect(formatChange(0)).toBe('+0.00');
    expect(formatPercent(1.2894)).toBe('+1.29%');
    expect(formatPercent(-0.5)).toBe('−0.50%');
  });

  it('uses four decimals for sub-unit moves', () => {
    expect(formatChange(0.0125)).toBe('+0.0125');
  });

  it('renders a dash rather than NaN', () => {
    expect(formatChange(NaN)).toBe('—');
    expect(formatPercent(NaN)).toBe('—');
  });
});

describe('formatUpdatedAt', () => {
  it('is empty when nothing has been fetched yet', () => {
    expect(formatUpdatedAt(null)).toBe('');
  });

  it('prefixes a time with "Updated"', () => {
    expect(formatUpdatedAt(Date.UTC(2024, 0, 1, 12, 0))).toMatch(/^Updated /);
  });
});

describe('describeMarketState', () => {
  it('maps the states the feed reports', () => {
    expect(describeMarketState('REGULAR')).toBe('Market open');
    expect(describeMarketState('PRE')).toBe('Pre-market');
    expect(describeMarketState('POST')).toBe('After hours');
    expect(describeMarketState('CLOSED')).toBe('Market closed');
  });

  it('says nothing for a state it does not recognise', () => {
    expect(describeMarketState('')).toBe('');
    expect(describeMarketState('SOMETHING_NEW')).toBe('');
  });
});

describe('normaliseSymbol', () => {
  it('upper-cases and trims user input', () => {
    expect(normaliseSymbol('  aapl ')).toBe('AAPL');
    expect(normaliseSymbol('vod.l')).toBe('VOD.L');
    expect(normaliseSymbol('   ')).toBe('');
  });
});
