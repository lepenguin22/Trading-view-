import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Quote } from '../api/types';
import { Theme, trendColor } from '../theme/theme';
import { formatChange, formatPrice } from '../utils/format';
import { ChangePill } from './ChangePill';
import { Sparkline } from './Sparkline';

type Props = {
  theme: Theme;
  symbol: string;
  quote: Quote | undefined;
  /** Message from the last refresh, if this symbol failed. */
  error: string | undefined;
  onPress: () => void;
  onLongPress: () => void;
};

const SPARK_WIDTH = 56;
const SPARK_HEIGHT = 28;

/** One watchlist row: identity on the left, sparkline and price on the right. */
export function QuoteRow({ theme, symbol, quote, error, onPress, onLongPress }: Props) {
  const change = quote?.change ?? 0;
  const color = trendColor(theme, change);

  // A cached quote from a previous session is still worth showing; it is just
  // labelled so nobody mistakes it for a live price.
  const stale = error !== undefined && quote !== undefined;

  const accessibilityLabel = quote
    ? `${symbol}, ${quote.name}, ${formatPrice(quote.price, quote.currency)}, ` +
      `${change >= 0 ? 'up' : 'down'} ${Math.abs(quote.changePercent).toFixed(2)} percent` +
      (stale ? ', last known price' : '')
    : `${symbol}, ${error ?? 'loading'}`;

  return (
    <Pressable
      onPress={onPress}
      onLongPress={onLongPress}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityHint="Opens the price chart. Long press for options."
      style={({ pressed }) => [
        styles.row,
        { backgroundColor: pressed ? theme.cardPressed : theme.card, borderColor: theme.border },
      ]}
    >
      <View style={styles.identity}>
        <Text style={[styles.symbol, { color: theme.text }]} numberOfLines={1}>
          {symbol}
        </Text>
        <Text style={[styles.name, { color: theme.textMuted }]} numberOfLines={1}>
          {quote?.name ?? (error !== undefined ? error : 'Loading…')}
        </Text>
      </View>

      {quote !== undefined && (
        <>
          <View style={styles.spark}>
            <Sparkline
              points={quote.spark}
              width={SPARK_WIDTH}
              height={SPARK_HEIGHT}
              color={stale ? theme.textFaint : color}
            />
          </View>

          <View style={styles.figures}>
            <Text style={[styles.price, { color: theme.text }]} numberOfLines={1}>
              {formatPrice(quote.price, quote.currency)}
            </Text>
            <View style={styles.changeLine}>
              <Text style={[styles.change, { color }]} numberOfLines={1}>
                {formatChange(quote.change)}
              </Text>
              <ChangePill theme={theme} changePercent={quote.changePercent} />
            </View>
          </View>
        </>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 10,
  },
  identity: { flex: 1, minWidth: 0 },
  symbol: { fontSize: 17, fontWeight: '700', letterSpacing: 0.2 },
  name: { fontSize: 13, marginTop: 2 },
  spark: { width: SPARK_WIDTH, height: SPARK_HEIGHT, justifyContent: 'center' },
  figures: { alignItems: 'flex-end' },
  price: { fontSize: 17, fontWeight: '600', fontVariant: ['tabular-nums'] },
  changeLine: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 3 },
  change: { fontSize: 13, fontWeight: '500', fontVariant: ['tabular-nums'] },
});
