import { useColorScheme } from 'react-native';

export type Theme = {
  dark: boolean;
  bg: string;
  card: string;
  cardPressed: string;
  border: string;
  text: string;
  textMuted: string;
  textFaint: string;
  up: string;
  down: string;
  flat: string;
  accent: string;
  danger: string;
  /** Fill behind the chart line, layered under the stroke. */
  chartFill: string;
};

const light: Theme = {
  dark: false,
  bg: '#F5F6F8',
  card: '#FFFFFF',
  cardPressed: '#ECEEF1',
  border: '#E2E5EA',
  text: '#0B0F14',
  textMuted: '#5C6672',
  textFaint: '#9AA3AE',
  up: '#0F9D58',
  down: '#D93025',
  flat: '#5C6672',
  accent: '#1A73E8',
  danger: '#D93025',
  chartFill: 'rgba(15,157,88,0.10)',
};

const dark: Theme = {
  dark: true,
  bg: '#0B0F14',
  card: '#151B23',
  cardPressed: '#1E262F',
  border: '#232C36',
  text: '#F2F5F8',
  textMuted: '#98A3B0',
  textFaint: '#6B7683',
  up: '#31C48D',
  down: '#F05252',
  flat: '#98A3B0',
  accent: '#5B9DF9',
  danger: '#F05252',
  chartFill: 'rgba(49,196,141,0.12)',
};

/** Follows the OS appearance setting; `userInterfaceStyle` is "automatic". */
export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? dark : light;
}

/** Colour for a change value: green up, red down, muted when unchanged. */
export function trendColor(theme: Theme, change: number): string {
  if (!Number.isFinite(change) || change === 0) return theme.flat;
  return change > 0 ? theme.up : theme.down;
}

export const themes = { light, dark };
