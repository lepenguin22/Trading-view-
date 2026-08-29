import { PricePoint } from '../api/types';

export type ChartGeometry = {
  /** SVG path for the price line. */
  line: string;
  /** Closed path for the tint under the line. */
  area: string;
  min: number;
  max: number;
  /** Screen x of each point, so callers can hit-test a touch. */
  xs: number[];
  ys: number[];
};

export type ChartSize = {
  width: number;
  height: number;
  /** Vertical inset so the line never clips against the top or bottom edge. */
  padding?: number;
};

/**
 * Projects a price series onto an SVG viewport.
 *
 * Points are spaced evenly by index rather than by timestamp: market data has
 * overnight and weekend gaps, and spacing by time would leave the chart mostly
 * empty air. This matches how every trading app draws it.
 */
export function buildChart(points: PricePoint[], size: ChartSize): ChartGeometry | null {
  const { width, height } = size;
  const padding = size.padding ?? 4;

  if (points.length === 0 || width <= 0 || height <= 0) return null;

  const values = points.map((p) => p.c);
  const min = Math.min(...values);
  const max = Math.max(...values);
  // A dead-flat series has no range to scale against; draw it down the middle.
  const span = max - min;
  const usableHeight = Math.max(height - padding * 2, 1);

  const xs: number[] = [];
  const ys: number[] = [];
  for (let i = 0; i < points.length; i++) {
    // A single point sits at the left edge rather than dividing by zero.
    const x = points.length === 1 ? 0 : (i / (points.length - 1)) * width;
    const ratio = span === 0 ? 0.5 : (points[i].c - min) / span;
    // SVG y grows downward, so the highest price maps to the smallest y.
    const y = padding + (1 - ratio) * usableHeight;
    xs.push(x);
    ys.push(y);
  }

  let line = `M ${round(xs[0])} ${round(ys[0])}`;
  for (let i = 1; i < xs.length; i++) {
    line += ` L ${round(xs[i])} ${round(ys[i])}`;
  }

  const area =
    `${line} L ${round(xs[xs.length - 1])} ${round(height)} ` +
    `L ${round(xs[0])} ${round(height)} Z`;

  return { line, area, min, max, xs, ys };
}

/** Index of the point nearest a touch x, for the scrubbing crosshair. */
export function nearestIndex(xs: number[], x: number): number {
  if (xs.length === 0) return -1;
  let best = 0;
  let bestDistance = Math.abs(xs[0] - x);
  for (let i = 1; i < xs.length; i++) {
    const distance = Math.abs(xs[i] - x);
    if (distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}

/** Keeps SVG path strings short; sub-pixel precision is invisible anyway. */
function round(n: number): number {
  return Math.round(n * 100) / 100;
}
