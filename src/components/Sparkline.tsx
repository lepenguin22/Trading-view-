import React from 'react';
import { View } from 'react-native';
import Svg, { Path } from 'react-native-svg';

import { PricePoint } from '../api/types';
import { buildChart } from '../utils/chart';

type Props = {
  points: PricePoint[];
  width: number;
  height: number;
  color: string;
};

/** The small trend line on each watchlist row. Decorative, so it is hidden
 *  from screen readers — the row already announces price and change. */
export function Sparkline({ points, width, height, color }: Props) {
  const chart = buildChart(points, { width, height, padding: 2 });

  if (chart === null) return <View style={{ width, height }} />;

  return (
    <Svg width={width} height={height} accessibilityElementsHidden importantForAccessibility="no">
      <Path d={chart.line} stroke={color} strokeWidth={1.5} fill="none" strokeLinejoin="round" />
    </Svg>
  );
}
