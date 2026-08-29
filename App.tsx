import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { Navigation } from './src/navigation';
import { WatchlistProvider } from './src/state/watchlist';

export default function App() {
  return (
    <SafeAreaProvider>
      <WatchlistProvider>
        <StatusBar style="auto" />
        <Navigation />
      </WatchlistProvider>
    </SafeAreaProvider>
  );
}
