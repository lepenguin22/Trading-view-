import { History, PricePoint, Quote, RangeKey, SearchResult } from './types';

/**
 * Pure parsers for the Yahoo Finance JSON payloads.
 *
 * These are deliberately kept free of `fetch` so they can be unit tested
 * against recorded fixtures. The upstream feed is undocumented and changes
 * shape occasionally, so every field is read defensively: a missing or
 * non-numeric field degrades the result rather than throwing.
 */

/** Thrown when a payload is structurally unusable (no result, or upstream error). */
export class FeedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FeedError';
  }
}

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null;
}

/** Pulls `chart.result[0]`, raising a FeedError if the payload carries one. */
function chartResult(payload: unknown): Record<string, unknown> {
  if (!isRecord(payload) || !isRecord(payload.chart)) {
    throw new FeedError('Unexpected response: no chart object');
  }
  const chart = payload.chart;
  const err = chart.error;
  if (isRecord(err)) {
    throw new FeedError(str(err.description) ?? str(err.code) ?? 'Upstream error');
  }
  const results = chart.result;
  if (!Array.isArray(results) || !isRecord(results[0])) {
    throw new FeedError('Unexpected response: no chart data');
  }
  return results[0];
}

/**
 * Zips the parallel `timestamp` and `indicators.quote[0].close` arrays into
 * points, dropping entries where either side is null. Yahoo pads both arrays
 * with nulls for halted or not-yet-traded intervals.
 */
export function parsePoints(result: Record<string, unknown>): PricePoint[] {
  const timestamps = Array.isArray(result.timestamp) ? result.timestamp : [];
  const indicators = isRecord(result.indicators) ? result.indicators : {};
  const quoteArr = Array.isArray(indicators.quote) ? indicators.quote : [];
  const quote0 = isRecord(quoteArr[0]) ? quoteArr[0] : {};
  const closes = Array.isArray(quote0.close) ? quote0.close : [];

  const points: PricePoint[] = [];
  const n = Math.min(timestamps.length, closes.length);
  for (let i = 0; i < n; i++) {
    const t = num(timestamps[i]);
    const c = num(closes[i]);
    if (t !== null && c !== null) points.push({ t, c });
  }
  return points;
}

/** Builds a watchlist quote from a `range=1d` chart payload. */
export function parseQuote(payload: unknown, fetchedAt = Date.now()): Quote {
  const result = chartResult(payload);
  const meta = isRecord(result.meta) ? result.meta : {};
  const points = parsePoints(result);
  const lastPoint = points.length > 0 ? points[points.length - 1].c : null;

  const symbol = str(meta.symbol) ?? '';
  if (!symbol) throw new FeedError('Unexpected response: no symbol');

  const price = num(meta.regularMarketPrice) ?? lastPoint;
  if (price === null) throw new FeedError(`No price available for ${symbol}`);

  // previousClose is the prior session's close; chartPreviousClose is the close
  // before the requested range begins. For a 1d range they agree, but only the
  // former is present on every payload.
  const previousClose =
    num(meta.previousClose) ??
    num(meta.chartPreviousClose) ??
    (points.length > 0 ? points[0].c : price);

  const change = price - previousClose;

  return {
    symbol,
    name: str(meta.longName) ?? str(meta.shortName) ?? symbol,
    price,
    previousClose,
    change,
    // A zero previous close would only happen on a malformed payload; guard
    // anyway so the UI never renders NaN%.
    changePercent: previousClose !== 0 ? (change / previousClose) * 100 : 0,
    currency: str(meta.currency) ?? 'USD',
    exchange: str(meta.fullExchangeName) ?? str(meta.exchangeName) ?? '',
    marketState: str(meta.marketState) ?? '',
    dayHigh: num(meta.regularMarketDayHigh),
    dayLow: num(meta.regularMarketDayLow),
    spark: points,
    fetchedAt,
  };
}

/** Builds a detail-screen series from a chart payload for the given range. */
export function parseHistory(payload: unknown, range: RangeKey): History {
  const result = chartResult(payload);
  const meta = isRecord(result.meta) ? result.meta : {};
  const points = parsePoints(result);

  if (points.length === 0) {
    throw new FeedError('No price history available for this range');
  }

  // For an intraday range the day's move is measured from the previous close,
  // not from the first tick of the session — otherwise an overnight gap
  // silently disappears from the chart's headline number.
  const baseline =
    range === '1D'
      ? (num(meta.chartPreviousClose) ?? num(meta.previousClose) ?? points[0].c)
      : points[0].c;

  const last = points[points.length - 1].c;
  const change = last - baseline;

  return {
    symbol: str(meta.symbol) ?? '',
    range,
    points,
    currency: str(meta.currency) ?? 'USD',
    first: baseline,
    last,
    change,
    changePercent: baseline !== 0 ? (change / baseline) * 100 : 0,
  };
}

/** Symbol types worth showing in search. Yahoo also returns futures, options
 *  and non-tradable entries that this app has nothing useful to do with. */
const SEARCHABLE_TYPES = new Set(['EQUITY', 'ETF', 'MUTUALFUND', 'INDEX', 'CRYPTOCURRENCY', 'CURRENCY']);

/** Parses the symbol lookup payload, dropping non-security hits. */
export function parseSearch(payload: unknown): SearchResult[] {
  if (!isRecord(payload) || !Array.isArray(payload.quotes)) return [];

  const out: SearchResult[] = [];
  for (const raw of payload.quotes) {
    if (!isRecord(raw)) continue;
    const symbol = str(raw.symbol);
    if (!symbol) continue;
    const type = (str(raw.quoteType) ?? '').toUpperCase();
    if (!SEARCHABLE_TYPES.has(type)) continue;
    out.push({
      symbol,
      name: str(raw.longname) ?? str(raw.shortname) ?? symbol,
      exchange: str(raw.exchDisp) ?? str(raw.exchange) ?? '',
      type,
    });
  }
  return out;
}
