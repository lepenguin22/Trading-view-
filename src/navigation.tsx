import React from 'react';
import { DarkTheme, DefaultTheme, NavigationContainer } from '@react-navigation/native';
import {
  createNativeStackNavigator,
  type NativeStackScreenProps,
} from '@react-navigation/native-stack';

import { DetailScreen } from './screens/DetailScreen';
import { SearchScreen } from './screens/SearchScreen';
import { WatchlistScreen } from './screens/WatchlistScreen';
import { useTheme } from './theme/theme';

export type RootStackParamList = {
  Watchlist: undefined;
  Search: undefined;
  Detail: { symbol: string };
};

export type RootScreenProps<T extends keyof RootStackParamList> = NativeStackScreenProps<
  RootStackParamList,
  T
>;

const Stack = createNativeStackNavigator<RootStackParamList>();

export function Navigation() {
  const theme = useTheme();

  // Hand React Navigation the same palette the screens use, so headers and the
  // gap behind a pushed screen match rather than flashing white in dark mode.
  const navTheme = {
    ...(theme.dark ? DarkTheme : DefaultTheme),
    colors: {
      ...(theme.dark ? DarkTheme : DefaultTheme).colors,
      background: theme.bg,
      card: theme.bg,
      text: theme.text,
      border: theme.border,
      primary: theme.accent,
    },
  };

  return (
    <NavigationContainer theme={navTheme}>
      <Stack.Navigator
        screenOptions={{
          headerLargeTitle: false,
          headerShadowVisible: false,
          contentStyle: { backgroundColor: theme.bg },
        }}
      >
        <Stack.Screen
          name="Watchlist"
          component={WatchlistScreen}
          options={{ title: 'Watchlist' }}
        />
        <Stack.Screen
          name="Search"
          component={SearchScreen}
          options={{ title: 'Add symbol', presentation: 'modal' }}
        />
        <Stack.Screen name="Detail" component={DetailScreen} options={{ title: '' }} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
