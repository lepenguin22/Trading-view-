/** A single point on a price series. */
export type PricePoint = {
  /** Epoch seconds, as returned by the upstream feed. */
  t: number;
  /** Close price for the interval. */
  c: number;
};

/** Everything the UI needs to render one row of the watchlist. */
export type Quote = {
  symbol: string;
  /** Human readable name, e.g. "Apple Inc.". Falls back to the symbol. */
  name: string;
  price: number;
  /** Previous close, used as the baseline for the day's change. */
  previousClose: number;
  change: number;
  changePercent: number;
  currency: string;
  /** Exchange short name, e.g. "NMS", "LSE". */
  exchange: string;
  /** "REGULAR" | "PRE" | "POST" | "CLOSED" | "" */
  marketState: string;
  dayHigh: number | null;
  dayLow: number | null;
  /** Intraday series for the row's sparkline. May be empty. */
  spark: PricePoint[];
  /** When this quote was fetched (epoch ms). */
  fetchedAt: number;
};

/** A price history series for the detail screen chart. */
export type History = {
  symbol: string;
  range: RangeKey;
  points: PricePoint[];
  currency: string;
  /** Baseline the range's change is measured against (first close in range). */
  first: number;
  last: number;
  change: number;
  changePercent: number;
};

/** A symbol search hit. */
export type SearchResult = {
  symbol: string;
  name: string;
  exchange: string;
  /** e.g. "EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY" */
  type: string;
};

export const RANGES = ['1D', '1W', '1M', '3M', '1Y', '5Y'] as const;
export type RangeKey = (typeof RANGES)[number];

/** Upstream range/interval pairs. Interval is chosen to keep each series
 *  in the low hundreds of points, which is plenty for a phone-width chart. */
export const RANGE_PARAMS: Record<RangeKey, { range: string; interval: string }> = {
  '1D': { range: '1d', interval: '5m' },
  '1W': { range: '5d', interval: '30m' },
  '1M': { range: '1mo', interval: '1d' },
  '3M': { range: '3mo', interval: '1d' },
  '1Y': { range: '1y', interval: '1d' },
  '5Y': { range: '5y', interval: '1wk' },
};
