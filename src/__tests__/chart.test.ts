import { buildChart, nearestIndex } from '../utils/chart';
import { PricePoint } from '../api/types';

const series = (values: number[]): PricePoint[] => values.map((c, i) => ({ t: i, c }));

describe('buildChart', () => {
  it('spreads points evenly across the width and inverts the y axis', () => {
    const chart = buildChart(series([10, 20, 30]), { width: 100, height: 50, padding: 0 });

    expect(chart).not.toBeNull();
    expect(chart!.xs).toEqual([0, 50, 100]);
    // The lowest price sits at the bottom (y = height), the highest at the top.
    expect(chart!.ys).toEqual([50, 25, 0]);
    expect(chart!.min).toBe(10);
    expect(chart!.max).toBe(30);
    expect(chart!.line).toBe('M 0 50 L 50 25 L 100 0');
  });

  it('insets the line by the padding so it does not clip', () => {
    const chart = buildChart(series([1, 2]), { width: 10, height: 100, padding: 8 });
    expect(chart!.ys).toEqual([92, 8]);
  });

  it('draws a flat series down the middle instead of dividing by zero', () => {
    const chart = buildChart(series([5, 5, 5]), { width: 90, height: 40, padding: 0 });
    expect(chart!.ys).toEqual([20, 20, 20]);
    expect(chart!.ys.every(Number.isFinite)).toBe(true);
  });

  it('handles a single point without producing NaN', () => {
    const chart = buildChart(series([42]), { width: 80, height: 20, padding: 0 });
    expect(chart!.xs).toEqual([0]);
    expect(chart!.ys.every(Number.isFinite)).toBe(true);
  });

  it('closes the area path along the bottom edge', () => {
    const chart = buildChart(series([10, 30]), { width: 100, height: 50, padding: 0 });
    expect(chart!.area).toBe('M 0 50 L 100 0 L 100 50 L 0 50 Z');
  });

  it('returns null when there is nothing to draw', () => {
    expect(buildChart([], { width: 100, height: 50 })).toBeNull();
    expect(buildChart(series([1, 2]), { width: 0, height: 50 })).toBeNull();
    expect(buildChart(series([1, 2]), { width: 100, height: 0 })).toBeNull();
  });
});

describe('nearestIndex', () => {
  const xs = [0, 25, 50, 75, 100];

  it('finds the closest point to a touch', () => {
    expect(nearestIndex(xs, 0)).toBe(0);
    expect(nearestIndex(xs, 26)).toBe(1);
    expect(nearestIndex(xs, 60)).toBe(2);
    expect(nearestIndex(xs, 99)).toBe(4);
  });

  it('clamps to the ends for touches beyond the plot', () => {
    expect(nearestIndex(xs, -40)).toBe(0);
    expect(nearestIndex(xs, 400)).toBe(4);
  });

  it('reports -1 when there is no series', () => {
    expect(nearestIndex([], 10)).toBe(-1);
  });
});
