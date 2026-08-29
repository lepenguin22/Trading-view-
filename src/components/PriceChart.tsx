import React, { useCallback, useMemo, useRef, useState } from 'react';
import { LayoutChangeEvent, PanResponder, StyleSheet, View } from 'react-native';
import Svg, { Circle, Line, Path } from 'react-native-svg';

import { PricePoint } from '../api/types';
import { Theme } from '../theme/theme';
import { buildChart, nearestIndex } from '../utils/chart';

type Props = {
  points: PricePoint[];
  color: string;
  fill: string;
  theme: Theme;
  height?: number;
  /** Price level the range's change is measured from; drawn as a dashed rule. */
  baseline?: number | null;
  /** Fires with the scrubbed index, or null when the finger lifts. */
  onScrub?: (index: number | null) => void;
};

const DEFAULT_HEIGHT = 220;
const PADDING = 10;

/**
 * The detail screen chart: a filled price line the user can drag along to read
 * off individual points. Drawn with plain SVG paths rather than a charting
 * library — the shapes are simple and this keeps the bundle small.
 */
export function PriceChart({
  points,
  color,
  fill,
  theme,
  height = DEFAULT_HEIGHT,
  baseline = null,
  onScrub,
}: Props) {
  const [width, setWidth] = useState(0);
  const [scrubIndex, setScrubIndex] = useState<number | null>(null);

  const chart = useMemo(
    () => buildChart(points, { width, height, padding: PADDING }),
    [points, width, height],
  );

  // The pan responder is created once, so it reads the live chart through a ref
  // rather than closing over a stale value.
  const chartRef = useRef(chart);
  chartRef.current = chart;
  const onScrubRef = useRef(onScrub);
  onScrubRef.current = onScrub;

  const handleTouch = useCallback((x: number) => {
    const current = chartRef.current;
    if (current === null) return;
    const index = nearestIndex(current.xs, x);
    setScrubIndex(index);
    onScrubRef.current?.(index);
  }, []);

  const endScrub = useCallback(() => {
    setScrubIndex(null);
    onScrubRef.current?.(null);
  }, []);

  const responder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        // Claim the gesture so the enclosing ScrollView does not steal a
        // horizontal drag mid-scrub.
        onPanResponderTerminationRequest: () => false,
        onPanResponderGrant: (e) => handleTouch(e.nativeEvent.locationX),
        onPanResponderMove: (e) => handleTouch(e.nativeEvent.locationX),
        onPanResponderRelease: endScrub,
        onPanResponderTerminate: endScrub,
      }),
    [handleTouch, endScrub],
  );

  const onLayout = useCallback((e: LayoutChangeEvent) => {
    setWidth(e.nativeEvent.layout.width);
  }, []);

  // Project the baseline price into chart space so the dashed rule lines up
  // with the series it is being compared against.
  const baselineY = useMemo(() => {
    if (chart === null || baseline === null || !Number.isFinite(baseline)) return null;
    if (baseline < chart.min || baseline > chart.max) return null;
    const span = chart.max - chart.min;
    if (span === 0) return null;
    const ratio = (baseline - chart.min) / span;
    return PADDING + (1 - ratio) * Math.max(height - PADDING * 2, 1);
  }, [chart, baseline, height]);

  return (
    <View
      style={[styles.container, { height }]}
      onLayout={onLayout}
      accessible
      accessibilityRole="image"
      accessibilityLabel="Price chart. Drag across it to read individual prices."
      {...responder.panHandlers}
    >
      {chart !== null && width > 0 && (
        <Svg width={width} height={height}>
          <Path d={chart.area} fill={fill} />

          {baselineY !== null && (
            <Line
              x1={0}
              y1={baselineY}
              x2={width}
              y2={baselineY}
              stroke={theme.textFaint}
              strokeWidth={1}
              strokeDasharray="3 4"
            />
          )}

          <Path
            d={chart.line}
            stroke={color}
            strokeWidth={2}
            fill="none"
            strokeLinejoin="round"
            strokeLinecap="round"
          />

          {scrubIndex !== null && scrubIndex < chart.xs.length && (
            <>
              <Line
                x1={chart.xs[scrubIndex]}
                y1={0}
                x2={chart.xs[scrubIndex]}
                y2={height}
                stroke={theme.textFaint}
                strokeWidth={1}
              />
              <Circle
                cx={chart.xs[scrubIndex]}
                cy={chart.ys[scrubIndex]}
                r={5}
                fill={color}
                stroke={theme.card}
                strokeWidth={2}
              />
            </>
          )}
        </Svg>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { width: '100%', justifyContent: 'center' },
});
