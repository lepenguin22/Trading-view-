import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { AppState, AppStateStatus } from 'react-native';

import { describeError, fetchQuote, fetchQuotes } from '../api/yahoo';
import { Quote } from '../api/types';
import { normaliseSymbol } from '../utils/format';
import {
  loadCachedQuotes,
  loadSymbols,
  saveCachedQuotes,
  saveSymbols,
} from './storage';

/** How often the watchlist re-polls while the app is in the foreground. */
const REFRESH_INTERVAL_MS = 60_000;

/** Treats any state that is not explicitly backgrounded as on screen. */
function isForeground(state: AppStateStatus | undefined): boolean {
  return state !== 'background' && state !== 'inactive';
}

type WatchlistValue = {
  /** Watchlist order, as the user arranged it. */
  symbols: string[];
  quotes: Record<string, Quote>;
  /** Per-symbol failure messages from the last refresh. */
  errors: Record<string, string>;
  /** True until the persisted watchlist has been read. */
  hydrating: boolean;
  refreshing: boolean;
  /** Epoch ms of the last refresh that returned at least one quote. */
  lastUpdated: number | null;
  refresh: () => Promise<void>;
  /** Resolves to an error message, or null when the symbol was added. */
  addSymbol: (symbol: string) => Promise<string | null>;
  removeSymbol: (symbol: string) => void;
  moveSymbol: (symbol: string, direction: -1 | 1) => void;
  has: (symbol: string) => boolean;
};

const WatchlistContext = createContext<WatchlistValue | null>(null);

export function WatchlistProvider({ children }: { children: React.ReactNode }) {
  const [symbols, setSymbols] = useState<string[]>([]);
  const [quotes, setQuotes] = useState<Record<string, Quote>>({});
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [hydrating, setHydrating] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<number | null>(null);

  // Reading `symbols` from a ref keeps refresh() stable, so the polling effect
  // below is not torn down and rebuilt every time the watchlist changes.
  const symbolsRef = useRef<string[]>([]);
  symbolsRef.current = symbols;

  // Lets an in-flight refresh be cancelled when a newer one starts or the
  // provider unmounts.
  const inFlight = useRef<AbortController | null>(null);

  const refresh = useCallback(async () => {
    const list = symbolsRef.current;
    if (list.length === 0) {
      setErrors({});
      return;
    }

    inFlight.current?.abort();
    const controller = new AbortController();
    inFlight.current = controller;

    setRefreshing(true);
    try {
      const { quotes: fresh, errors: failed } = await fetchQuotes(list, controller.signal);
      if (controller.signal.aborted) return;

      if (fresh.length > 0) {
        setQuotes((prev) => {
          const next = { ...prev };
          for (const q of fresh) next[q.symbol] = q;
          void saveCachedQuotes(next);
          return next;
        });
        setLastUpdated(Date.now());
      }
      setErrors(failed);
    } finally {
      if (!controller.signal.aborted) setRefreshing(false);
      if (inFlight.current === controller) inFlight.current = null;
    }
  }, []);

  // Hydrate from storage, then do a first refresh.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [saved, cached] = await Promise.all([loadSymbols(), loadCachedQuotes()]);
      if (cancelled) return;
      symbolsRef.current = saved;
      setSymbols(saved);
      setQuotes(cached);
      setHydrating(false);
      void refresh();
    })();
    return () => {
      cancelled = true;
      inFlight.current?.abort();
    };
  }, [refresh]);

  // Poll while the app is in the foreground, and refresh on the way back in.
  // Polling in the background would burn battery for a screen nobody is looking at.
  useEffect(() => {
    if (hydrating) return;

    let timer: ReturnType<typeof setInterval> | null = null;

    const start = () => {
      if (timer === null) timer = setInterval(() => void refresh(), REFRESH_INTERVAL_MS);
    };
    const stop = () => {
      if (timer !== null) {
        clearInterval(timer);
        timer = null;
      }
    };

    const onAppStateChange = (state: AppStateStatus) => {
      if (isForeground(state)) {
        void refresh();
        start();
      } else {
        stop();
      }
    };

    // Tested against backgrounding rather than for 'active': the current state
    // is briefly 'unknown' during an Android cold start, and checking for
    // 'active' there would leave polling switched off until the app was next
    // backgrounded and reopened.
    if (isForeground(AppState.currentState)) start();
    const sub = AppState.addEventListener('change', onAppStateChange);

    return () => {
      stop();
      sub.remove();
    };
  }, [hydrating, refresh]);

  const persist = useCallback((next: string[]) => {
    symbolsRef.current = next;
    setSymbols(next);
    void saveSymbols(next);
  }, []);

  const addSymbol = useCallback(
    async (input: string): Promise<string | null> => {
      const symbol = normaliseSymbol(input);
      if (!symbol) return 'Enter a ticker symbol.';
      if (symbolsRef.current.includes(symbol)) return `${symbol} is already on your watchlist.`;

      // Fetch before committing so a typo never lands a dead row on the list.
      try {
        const quote = await fetchQuote(symbol);
        setQuotes((prev) => {
          const next = { ...prev, [quote.symbol]: quote };
          void saveCachedQuotes(next);
          return next;
        });
        persist([...symbolsRef.current, quote.symbol]);
        setLastUpdated(Date.now());
        return null;
      } catch (err) {
        return describeError(err);
      }
    },
    [persist],
  );

  const removeSymbol = useCallback(
    (symbol: string) => {
      persist(symbolsRef.current.filter((s) => s !== symbol));
      setErrors((prev) => {
        const { [symbol]: _removed, ...rest } = prev;
        return rest;
      });
    },
    [persist],
  );

  /** Nudges a symbol one place up (-1) or down (1); a no-op at either end. */
  const moveSymbol = useCallback(
    (symbol: string, direction: -1 | 1) => {
      const current = symbolsRef.current;
      const from = current.indexOf(symbol);
      const to = from + direction;
      if (from === -1 || to < 0 || to >= current.length) return;
      const next = [...current];
      next[from] = current[to];
      next[to] = symbol;
      persist(next);
    },
    [persist],
  );

  const has = useCallback((symbol: string) => symbols.includes(normaliseSymbol(symbol)), [symbols]);

  const value = useMemo<WatchlistValue>(
    () => ({
      symbols,
      quotes,
      errors,
      hydrating,
      refreshing,
      lastUpdated,
      refresh,
      addSymbol,
      removeSymbol,
      moveSymbol,
      has,
    }),
    [
      symbols,
      quotes,
      errors,
      hydrating,
      refreshing,
      lastUpdated,
      refresh,
      addSymbol,
      removeSymbol,
      moveSymbol,
      has,
    ],
  );

  return <WatchlistContext.Provider value={value}>{children}</WatchlistContext.Provider>;
}

export function useWatchlist(): WatchlistValue {
  const ctx = useContext(WatchlistContext);
  if (ctx === null) throw new Error('useWatchlist must be used inside a WatchlistProvider');
  return ctx;
}
