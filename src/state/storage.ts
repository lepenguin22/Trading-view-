import AsyncStorage from '@react-native-async-storage/async-storage';

import { Quote } from '../api/types';

const SYMBOLS_KEY = 'ticker.watchlist.symbols.v1';
const QUOTES_KEY = 'ticker.watchlist.quotes.v1';

/** Shown on first launch so the app is not an empty screen. */
export const DEFAULT_SYMBOLS = ['AAPL', 'MSFT', 'NVDA', 'AMZN'];

/**
 * Storage is best-effort: a read failure means the watchlist starts from the
 * defaults, and a write failure means this change is not carried across a
 * relaunch. Neither is worth interrupting the user for, so both are swallowed.
 */

export async function loadSymbols(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(SYMBOLS_KEY);
    if (raw === null) return DEFAULT_SYMBOLS;
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return DEFAULT_SYMBOLS;
    return parsed.filter((s): s is string => typeof s === 'string' && s.length > 0);
  } catch {
    return DEFAULT_SYMBOLS;
  }
}

export async function saveSymbols(symbols: string[]): Promise<void> {
  try {
    await AsyncStorage.setItem(SYMBOLS_KEY, JSON.stringify(symbols));
  } catch {
    // Ignore: the in-memory watchlist is still correct for this session.
  }
}

/**
 * Quotes are cached only so a cold start shows prices immediately instead of
 * empty rows. They are always refreshed on mount, and the UI marks them stale.
 */
export async function loadCachedQuotes(): Promise<Record<string, Quote>> {
  try {
    const raw = await AsyncStorage.getItem(QUOTES_KEY);
    if (raw === null) return {};
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return {};
    return parsed as Record<string, Quote>;
  } catch {
    return {};
  }
}

export async function saveCachedQuotes(quotes: Record<string, Quote>): Promise<void> {
  try {
    await AsyncStorage.setItem(QUOTES_KEY, JSON.stringify(quotes));
  } catch {
    // Ignore: caching is an optimisation, not a correctness requirement.
  }
}
