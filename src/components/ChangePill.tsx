import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Theme, trendColor } from '../theme/theme';
import { formatPercent } from '../utils/format';

type Props = {
  theme: Theme;
  changePercent: number;
  /** Larger pill for the detail screen header. */
  large?: boolean;
};

/** Tinted percentage badge. Colour alone never carries the meaning — the
 *  sign is always in the text too, for colour-blind readers. */
export function ChangePill({ theme, changePercent, large = false }: Props) {
  const color = trendColor(theme, changePercent);

  return (
    <View style={[styles.pill, large && styles.pillLarge, { backgroundColor: color + '1F' }]}>
      <Text style={[styles.text, large && styles.textLarge, { color }]}>
        {formatPercent(changePercent)}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 7,
    minWidth: 74,
    alignItems: 'center',
  },
  pillLarge: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: 9, minWidth: 92 },
  text: { fontSize: 13, fontWeight: '600', fontVariant: ['tabular-nums'] },
  textLarge: { fontSize: 16 },
});
