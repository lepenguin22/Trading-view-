import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import * as Haptics from 'expo-haptics';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { describeError, fetchHistory } from '../api/yahoo';
import { History, RANGES, RangeKey } from '../api/types';
import { ChangePill } from '../components/ChangePill';
import { PriceChart } from '../components/PriceChart';
import { useWatchlist } from '../state/watchlist';
import { Theme, trendColor, useTheme } from '../theme/theme';
import {
  describeMarketState,
  formatChange,
  formatPointDate,
  formatPrice,
} from '../utils/format';
import type { RootScreenProps } from '../navigation';

export function DetailScreen({ route, navigation }: RootScreenProps<'Detail'>) {
  const { symbol } = route.params;
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { quotes, addSymbol, removeSymbol, has } = useWatchlist();

  const quote = quotes[symbol];
  const onWatchlist = has(symbol);

  const [range, setRange] = useState<RangeKey>('1D');
  const [history, setHistory] = useState<History | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scrubIndex, setScrubIndex] = useState<number | null>(null);
  // Bumped by "Try again"; setting `range` to its current value would not
  // re-run the fetch effect.
  const [reloadNonce, setReloadNonce] = useState(0);

  const inFlight = useRef<AbortController | null>(null);

  useEffect(() => {
    navigation.setOptions({ title: symbol });
  }, [navigation, symbol]);

  useEffect(() => {
    inFlight.current?.abort();
    const controller = new AbortController();
    inFlight.current = controller;

    setLoading(true);
    setError(null);
    setScrubIndex(null);

    (async () => {
      try {
        const result = await fetchHistory(symbol, range, controller.signal);
        if (!controller.signal.aborted) setHistory(result);
      } catch (err) {
        if (!controller.signal.aborted) {
          setHistory(null);
          setError(describeError(err));
        }
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();

    return () => controller.abort();
  }, [symbol, range, reloadNonce]);

  const onSelectRange = useCallback((next: RangeKey) => {
    void Haptics.selectionAsync();
    setRange(next);
  }, []);

  // While scrubbing, the header reports the point under the finger; otherwise
  // it reports the latest price for the selected range.
  const headline = useMemo(() => {
    if (history === null) return null;

    if (scrubIndex !== null && scrubIndex < history.points.length) {
      const point = history.points[scrubIndex];
      const change = point.c - history.first;
      return {
        price: point.c,
        change,
        changePercent: history.first !== 0 ? (change / history.first) * 100 : 0,
        caption: formatPointDate(point.t, range === '1D' || range === '1W'),
      };
    }

    return {
      price: history.last,
      change: history.change,
      changePercent: history.changePercent,
      caption:
        range === '1D'
          ? (describeMarketState(quote?.marketState ?? '') || 'Today')
          : `Past ${RANGE_LABELS[range]}`,
    };
  }, [history, scrubIndex, range, quote?.marketState]);

  const currency = history?.currency ?? quote?.currency ?? 'USD';
  const color = trendColor(theme, headline?.change ?? 0);

  return (
    <ScrollView
      style={{ backgroundColor: theme.bg }}
      contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 28 }]}
      // A vertical scroll must not fight the chart's horizontal scrub gesture.
      scrollEnabled={scrubIndex === null}
    >
      <View style={styles.header}>
        <Text style={[styles.name, { color: theme.textMuted }]} numberOfLines={2}>
          {quote?.name ?? symbol}
        </Text>

        <Text style={[styles.price, { color: theme.text }]}>
          {headline ? formatPrice(headline.price, currency) : '—'}
        </Text>

        <View style={styles.changeRow}>
          {headline && (
            <>
              <Text style={[styles.change, { color }]}>{formatChange(headline.change)}</Text>
              <ChangePill theme={theme} changePercent={headline.changePercent} large />
            </>
          )}
        </View>

        <Text style={[styles.caption, { color: theme.textFaint }]}>{headline?.caption ?? ''}</Text>
      </View>

      <View style={styles.chartArea}>
        {loading && history === null ? (
          <View style={[styles.chartPlaceholder, styles.centre]}>
            <ActivityIndicator color={theme.textMuted} />
          </View>
        ) : error !== null ? (
          <View style={[styles.chartPlaceholder, styles.centre]}>
            <Text style={[styles.errorText, { color: theme.danger }]}>{error}</Text>
            <Pressable
              onPress={() => setReloadNonce((n) => n + 1)}
              accessibilityRole="button"
              style={({ pressed }) => [
                styles.retry,
                { borderColor: theme.border, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <Text style={{ color: theme.accent, fontWeight: '600' }}>Try again</Text>
            </Pressable>
          </View>
        ) : history !== null ? (
          <PriceChart
            points={history.points}
            color={color}
            fill={color + '1A'}
            theme={theme}
            baseline={history.first}
            onScrub={setScrubIndex}
          />
        ) : null}

        {/* Keep the old chart on screen, dimmed, while a new range loads. */}
        {loading && history !== null && (
          <View style={styles.chartSpinner} pointerEvents="none">
            <ActivityIndicator color={theme.textMuted} />
          </View>
        )}
      </View>

      <View style={styles.ranges}>
        {RANGES.map((r) => {
          const active = r === range;
          return (
            <Pressable
              key={r}
              onPress={() => onSelectRange(r)}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              accessibilityLabel={`Show ${RANGE_LABELS[r]}`}
              style={[
                styles.rangeButton,
                active && { backgroundColor: color + '22' },
              ]}
            >
              <Text
                style={[
                  styles.rangeLabel,
                  { color: active ? color : theme.textMuted, fontWeight: active ? '700' : '500' },
                ]}
              >
                {r}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {quote !== undefined && <Stats theme={theme} currency={currency} quote={quote} />}

      <Pressable
        onPress={() => (onWatchlist ? removeSymbol(symbol) : void addSymbol(symbol))}
        accessibilityRole="button"
        style={({ pressed }) => [
          styles.watchButton,
          {
            borderColor: onWatchlist ? theme.border : theme.accent,
            backgroundColor: onWatchlist ? 'transparent' : theme.accent,
            opacity: pressed ? 0.8 : 1,
          },
        ]}
      >
        <Text
          style={[styles.watchLabel, { color: onWatchlist ? theme.textMuted : '#FFFFFF' }]}
        >
          {onWatchlist ? 'Remove from watchlist' : 'Add to watchlist'}
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function Stats({
  theme,
  currency,
  quote,
}: {
  theme: Theme;
  currency: string;
  quote: { previousClose: number; dayHigh: number | null; dayLow: number | null; exchange: string };
}) {
  const rows: [string, string][] = [
    ['Previous close', formatPrice(quote.previousClose, currency)],
    ['Day high', quote.dayHigh !== null ? formatPrice(quote.dayHigh, currency) : '—'],
    ['Day low', quote.dayLow !== null ? formatPrice(quote.dayLow, currency) : '—'],
    ['Exchange', quote.exchange || '—'],
  ];

  return (
    <View style={[styles.stats, { backgroundColor: theme.card, borderColor: theme.border }]}>
      {rows.map(([label, value], i) => (
        <View
          key={label}
          style={[
            styles.statRow,
            i < rows.length - 1 && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.border },
          ]}
        >
          <Text style={[styles.statLabel, { color: theme.textMuted }]}>{label}</Text>
          <Text style={[styles.statValue, { color: theme.text }]}>{value}</Text>
        </View>
      ))}
    </View>
  );
}

const RANGE_LABELS: Record<RangeKey, string> = {
  '1D': 'day',
  '1W': 'week',
  '1M': 'month',
  '3M': '3 months',
  '1Y': 'year',
  '5Y': '5 years',
};

const styles = StyleSheet.create({
  content: { padding: 16 },
  centre: { alignItems: 'center', justifyContent: 'center' },
  header: { marginBottom: 8 },
  name: { fontSize: 15 },
  price: { fontSize: 36, fontWeight: '700', marginTop: 4, fontVariant: ['tabular-nums'] },
  changeRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 6, minHeight: 30 },
  change: { fontSize: 17, fontWeight: '600', fontVariant: ['tabular-nums'] },
  caption: { fontSize: 13, marginTop: 6 },
  chartArea: { marginTop: 12, justifyContent: 'center' },
  chartPlaceholder: { height: 220 },
  chartSpinner: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorText: { fontSize: 14, textAlign: 'center', paddingHorizontal: 24 },
  retry: { marginTop: 14, paddingHorizontal: 18, paddingVertical: 9, borderRadius: 10, borderWidth: StyleSheet.hairlineWidth },
  ranges: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 14, marginBottom: 4 },
  rangeButton: { flex: 1, alignItems: 'center', paddingVertical: 8, marginHorizontal: 2, borderRadius: 9 },
  rangeLabel: { fontSize: 14 },
  stats: { marginTop: 20, borderRadius: 14, borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: 14 },
  statRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 13 },
  statLabel: { fontSize: 14 },
  statValue: { fontSize: 14, fontWeight: '600', fontVariant: ['tabular-nums'] },
  watchButton: { marginTop: 20, paddingVertical: 14, borderRadius: 13, borderWidth: 1, alignItems: 'center' },
  watchLabel: { fontSize: 15, fontWeight: '600' },
});
