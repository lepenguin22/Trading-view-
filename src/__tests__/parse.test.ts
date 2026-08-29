import { FeedError, parseHistory, parsePoints, parseQuote, parseSearch } from '../api/parse';

import chart1d from './fixtures/chart-1d.json';
import chart1y from './fixtures/chart-1y.json';
import chartEmpty from './fixtures/chart-empty.json';
import chartError from './fixtures/chart-error.json';
import search from './fixtures/search.json';

describe('parseQuote', () => {
  it('reads price, name and day change from a 1d chart payload', () => {
    const q = parseQuote(chart1d, 1_700_000_000_000);

    expect(q.symbol).toBe('AAPL');
    expect(q.name).toBe('Apple Inc.');
    expect(q.price).toBe(196.5);
    expect(q.previousClose).toBe(194);
    expect(q.change).toBeCloseTo(2.5, 10);
    expect(q.changePercent).toBeCloseTo((2.5 / 194) * 100, 10);
    expect(q.currency).toBe('USD');
    expect(q.exchange).toBe('NasdaqGS');
    expect(q.marketState).toBe('REGULAR');
    expect(q.dayHigh).toBe(197.1);
    expect(q.dayLow).toBe(193.8);
    expect(q.fetchedAt).toBe(1_700_000_000_000);
  });

  it('drops intervals whose close is null so the sparkline has no gaps', () => {
    const q = parseQuote(chart1d);
    // The fixture has five timestamps; the middle close is null.
    expect(q.spark).toHaveLength(4);
    expect(q.spark.map((p) => p.c)).toEqual([194.2, 195, 195.8, 196.5]);
    expect(q.spark.every((p) => Number.isFinite(p.t))).toBe(true);
  });

  it('falls back to the symbol when no long or short name is present', () => {
    const q = parseQuote(chartEmpty);
    expect(q.name).toBe('ZZZZ');
  });

  it('still produces a quote when the series is empty', () => {
    // A thinly traded ticker can return meta with no intraday bars at all.
    const q = parseQuote(chartEmpty);
    expect(q.price).toBe(1.23);
    expect(q.spark).toEqual([]);
  });

  it('raises a FeedError carrying the upstream description', () => {
    expect(() => parseQuote(chartError)).toThrow(FeedError);
    expect(() => parseQuote(chartError)).toThrow('No data found, symbol may be delisted');
  });

  it('raises a FeedError on a structurally unusable payload', () => {
    expect(() => parseQuote({})).toThrow(FeedError);
    expect(() => parseQuote(null)).toThrow(FeedError);
    expect(() => parseQuote({ chart: { result: [] } })).toThrow(FeedError);
  });
});

describe('parseHistory', () => {
  it('measures a 1D range against the previous close, not the first tick', () => {
    // chartPreviousClose is 194, the first tick is 194.2 — an overnight gap
    // that must not be swallowed.
    const h = parseHistory(chart1d, '1D');
    expect(h.first).toBe(194);
    expect(h.last).toBe(196.5);
    expect(h.change).toBeCloseTo(2.5, 10);
  });

  it('measures a longer range against the first close in the range', () => {
    const h = parseHistory(chart1y, '1Y');
    expect(h.symbol).toBe('VOD.L');
    expect(h.currency).toBe('GBp');
    expect(h.first).toBe(70);
    expect(h.last).toBe(78.4);
    expect(h.change).toBeCloseTo(8.4, 10);
    expect(h.changePercent).toBeCloseTo((8.4 / 70) * 100, 10);
    expect(h.points).toHaveLength(3);
  });

  it('raises rather than returning an empty chart', () => {
    expect(() => parseHistory(chartEmpty, '1M')).toThrow(FeedError);
  });
});

describe('parsePoints', () => {
  it('stops at the shorter of the timestamp and close arrays', () => {
    const points = parsePoints({
      timestamp: [1, 2, 3],
      indicators: { quote: [{ close: [10, 11] }] },
    });
    expect(points).toEqual([
      { t: 1, c: 10 },
      { t: 2, c: 11 },
    ]);
  });

  it('returns an empty series when indicators are missing entirely', () => {
    expect(parsePoints({ timestamp: [1, 2] })).toEqual([]);
    expect(parsePoints({})).toEqual([]);
  });
});

describe('parseSearch', () => {
  it('keeps tradable securities and drops options and editorial hits', () => {
    const results = parseSearch(search);
    expect(results.map((r) => r.symbol)).toEqual(['AAPL', 'AAPL.MX', 'IYW', 'BTC-USD']);
  });

  it('prefers the long name and the display exchange', () => {
    const [apple, appleMx] = parseSearch(search);
    expect(apple).toEqual({
      symbol: 'AAPL',
      name: 'Apple Inc.',
      exchange: 'NASDAQ',
      type: 'EQUITY',
    });
    // AAPL.MX has no longname, so the short name stands in.
    expect(appleMx.name).toBe('Apple Inc.');
    expect(appleMx.exchange).toBe('Mexico');
  });

  it('returns an empty list for a malformed payload', () => {
    expect(parseSearch({})).toEqual([]);
    expect(parseSearch(null)).toEqual([]);
    expect(parseSearch({ quotes: 'nope' })).toEqual([]);
  });
});
