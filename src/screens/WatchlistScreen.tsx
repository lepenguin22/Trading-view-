import React, { useCallback } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { QuoteRow } from '../components/QuoteRow';
import { useWatchlist } from '../state/watchlist';
import { Theme, useTheme } from '../theme/theme';
import { formatUpdatedAt } from '../utils/format';
import type { RootScreenProps } from '../navigation';

export function WatchlistScreen({ navigation }: RootScreenProps<'Watchlist'>) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const {
    symbols,
    quotes,
    errors,
    hydrating,
    refreshing,
    lastUpdated,
    refresh,
    removeSymbol,
    moveSymbol,
  } = useWatchlist();

  /** Long press opens the row's actions; there is no room for them inline. */
  const showRowActions = useCallback(
    (symbol: string) => {
      const index = symbols.indexOf(symbol);
      Alert.alert(symbol, 'What would you like to do?', [
        ...(index > 0
          ? [{ text: 'Move up', onPress: () => moveSymbol(symbol, -1) }]
          : []),
        ...(index >= 0 && index < symbols.length - 1
          ? [{ text: 'Move down', onPress: () => moveSymbol(symbol, 1) }]
          : []),
        {
          text: 'Remove from watchlist',
          style: 'destructive' as const,
          onPress: () => removeSymbol(symbol),
        },
        { text: 'Cancel', style: 'cancel' as const },
      ]);
    },
    [symbols, moveSymbol, removeSymbol],
  );

  if (hydrating) {
    return (
      <View style={[styles.centre, { backgroundColor: theme.bg }]}>
        <ActivityIndicator color={theme.textMuted} />
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: theme.bg }]}>
      <FlatList
        data={symbols}
        keyExtractor={(symbol) => symbol}
        contentContainerStyle={[
          styles.listContent,
          { paddingBottom: insets.bottom + 96 },
          symbols.length === 0 && styles.listContentEmpty,
        ]}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={refresh}
            tintColor={theme.textMuted}
            colors={[theme.accent]}
          />
        }
        ListHeaderComponent={
          symbols.length > 0 && lastUpdated !== null ? (
            <Text style={[styles.updated, { color: theme.textFaint }]}>
              {formatUpdatedAt(lastUpdated)}
            </Text>
          ) : null
        }
        ListEmptyComponent={<EmptyState theme={theme} onAdd={() => navigation.navigate('Search')} />}
        renderItem={({ item }) => (
          <QuoteRow
            theme={theme}
            symbol={item}
            quote={quotes[item]}
            error={errors[item]}
            onPress={() => navigation.navigate('Detail', { symbol: item })}
            onLongPress={() => showRowActions(item)}
          />
        )}
      />

      <Pressable
        onPress={() => navigation.navigate('Search')}
        accessibilityRole="button"
        accessibilityLabel="Add a symbol to your watchlist"
        style={({ pressed }) => [
          styles.fab,
          {
            backgroundColor: theme.accent,
            bottom: insets.bottom + 24,
            opacity: pressed ? 0.85 : 1,
          },
        ]}
      >
        <Text style={styles.fabLabel}>+</Text>
      </Pressable>
    </View>
  );
}

function EmptyState({ theme, onAdd }: { theme: Theme; onAdd: () => void }) {
  return (
    <View style={styles.empty}>
      <Text style={[styles.emptyTitle, { color: theme.text }]}>No symbols yet</Text>
      <Text style={[styles.emptyBody, { color: theme.textMuted }]}>
        Add a company or fund to start tracking its share price.
      </Text>
      <Pressable
        onPress={onAdd}
        accessibilityRole="button"
        style={({ pressed }) => [
          styles.emptyButton,
          { backgroundColor: theme.accent, opacity: pressed ? 0.85 : 1 },
        ]}
      >
        <Text style={styles.emptyButtonLabel}>Add a symbol</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  centre: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  listContent: { padding: 14 },
  listContentEmpty: { flexGrow: 1, justifyContent: 'center' },
  separator: { height: 8 },
  updated: { fontSize: 12, textAlign: 'center', marginBottom: 10 },
  empty: { alignItems: 'center', paddingHorizontal: 32 },
  emptyTitle: { fontSize: 19, fontWeight: '700' },
  emptyBody: { fontSize: 15, textAlign: 'center', marginTop: 8, lineHeight: 21 },
  emptyButton: { marginTop: 20, paddingHorizontal: 20, paddingVertical: 11, borderRadius: 11 },
  emptyButtonLabel: { color: '#FFFFFF', fontSize: 15, fontWeight: '600' },
  fab: {
    position: 'absolute',
    right: 20,
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.25,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 5,
  },
  fabLabel: { color: '#FFFFFF', fontSize: 30, lineHeight: 34, fontWeight: '400' },
});
