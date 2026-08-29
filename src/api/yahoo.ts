import { parseHistory, parseQuote, parseSearch, FeedError } from './parse';
import { History, Quote, RANGE_PARAMS, RangeKey, SearchResult } from './types';

/**
 * Thin client over Yahoo Finance's public chart/search endpoints.
 *
 * These endpoints need no API key, but they are undocumented: they rate limit,
 * they occasionally return HTML error pages, and one host can be unhealthy
 * while the other is fine. Every request therefore falls back from query1 to
 * query2 and is bounded by a timeout.
 */

const HOSTS = ['https://query1.finance.yahoo.com', 'https://query2.finance.yahoo.com'];

const REQUEST_TIMEOUT_MS = 12_000;

// Yahoo returns 429 to clients that look automated, so present a browser UA.
const HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  Accept: 'application/json',
};

/** A network/HTTP level failure, as opposed to a malformed payload (FeedError). */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NetworkError';
  }
}

async function fetchJsonFrom(url: string, signal?: AbortSignal): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  // Forward an upstream cancellation (screen unmounted, query superseded).
  const onAbort = () => controller.abort();
  signal?.addEventListener('abort', onAbort);

  try {
    const res = await fetch(url, { headers: HEADERS, signal: controller.signal });
    if (!res.ok) {
      throw new NetworkError(
        res.status === 429
          ? 'Rate limited by Yahoo Finance. Wait a moment and try again.'
          : `Request failed (HTTP ${res.status})`,
      );
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', onAbort);
  }
}

/** Issues `path` against each host in turn, returning the first JSON body. */
async function fetchJson(path: string, signal?: AbortSignal): Promise<unknown> {
  let lastError: unknown;
  for (const host of HOSTS) {
    try {
      return await fetchJsonFrom(host + path, signal);
    } catch (err) {
      // An explicit cancellation is not a host failure — don't retry it.
      if (signal?.aborted) throw err;
      lastError = err;
    }
  }
  if (lastError instanceof NetworkError) throw lastError;
  throw new NetworkError('Could not reach Yahoo Finance. Check your connection.');
}

function chartPath(symbol: string, range: string, interval: string): string {
  return (
    `/v8/finance/chart/${encodeURIComponent(symbol)}` +
    `?range=${range}&interval=${interval}&includePrePost=false`
  );
}

/** Fetches the current quote plus an intraday series for the sparkline. */
export async function fetchQuote(symbol: string, signal?: AbortSignal): Promise<Quote> {
  const payload = await fetchJson(chartPath(symbol, '1d', '5m'), signal);
  return parseQuote(payload);
}

/**
 * Fetches quotes for many symbols at once.
 *
 * Yahoo's batch quote endpoint now requires a session crumb, so this fans out
 * one chart request per symbol instead. Failures are returned per-symbol
 * rather than rejecting the batch: one delisted ticker should not blank the
 * whole watchlist.
 */
export async function fetchQuotes(
  symbols: string[],
  signal?: AbortSignal,
): Promise<{ quotes: Quote[]; errors: Record<string, string> }> {
  const settled = await Promise.allSettled(symbols.map((s) => fetchQuote(s, signal)));

  const quotes: Quote[] = [];
  const errors: Record<string, string> = {};
  settled.forEach((outcome, i) => {
    if (outcome.status === 'fulfilled') {
      quotes.push(outcome.value);
    } else {
      errors[symbols[i]] = describeError(outcome.reason);
    }
  });
  return { quotes, errors };
}

/** Fetches a price series for the detail screen. */
export async function fetchHistory(
  symbol: string,
  range: RangeKey,
  signal?: AbortSignal,
): Promise<History> {
  const { range: r, interval } = RANGE_PARAMS[range];
  const payload = await fetchJson(chartPath(symbol, r, interval), signal);
  return parseHistory(payload, range);
}

/** Looks up symbols by company name or ticker. */
export async function searchSymbols(
  query: string,
  signal?: AbortSignal,
): Promise<SearchResult[]> {
  const q = query.trim();
  if (!q) return [];
  const payload = await fetchJson(
    `/v1/finance/search?q=${encodeURIComponent(q)}&quotesCount=20&newsCount=0&listsCount=0`,
    signal,
  );
  return parseSearch(payload);
}

/** Turns any thrown value into something worth showing a user. */
export function describeError(err: unknown): string {
  if (err instanceof NetworkError || err instanceof FeedError) return err.message;
  if (err instanceof Error) {
    if (err.name === 'AbortError') return 'Request timed out.';
    return err.message;
  }
  return 'Something went wrong.';
}
