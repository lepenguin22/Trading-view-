import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Keyboard,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { describeError, searchSymbols } from '../api/yahoo';
import { SearchResult } from '../api/types';
import { useWatchlist } from '../state/watchlist';
import { useTheme } from '../theme/theme';
import type { RootScreenProps } from '../navigation';

/** Wait this long after the last keystroke before querying. */
const DEBOUNCE_MS = 350;

export function SearchScreen({ navigation }: RootScreenProps<'Search'>) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { addSymbol, has } = useWatchlist();

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState<string | null>(null);

  // Cancels the previous request so out-of-order responses can't overwrite
  // results for a query the user has already moved past.
  const inFlight = useRef<AbortController | null>(null);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      inFlight.current?.abort();
      setResults([]);
      setError(null);
      setSearching(false);
      return;
    }

    const timer = setTimeout(async () => {
      inFlight.current?.abort();
      const controller = new AbortController();
      inFlight.current = controller;

      setSearching(true);
      setError(null);
      try {
        const found = await searchSymbols(trimmed, controller.signal);
        if (!controller.signal.aborted) setResults(found);
      } catch (err) {
        if (!controller.signal.aborted) {
          setResults([]);
          setError(describeError(err));
        }
      } finally {
        if (!controller.signal.aborted) setSearching(false);
      }
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => () => inFlight.current?.abort(), []);

  const onAdd = useCallback(
    async (symbol: string) => {
      Keyboard.dismiss();
      setAdding(symbol);
      const failure = await addSymbol(symbol);
      setAdding(null);
      if (failure === null) {
        navigation.goBack();
      } else {
        setError(failure);
      }
    },
    [addSymbol, navigation],
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.bg }]}>
      <View style={styles.searchBar}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Company name or ticker"
          placeholderTextColor={theme.textFaint}
          autoCapitalize="characters"
          autoCorrect={false}
          autoFocus
          returnKeyType="search"
          accessibilityLabel="Search for a company or ticker symbol"
          style={[
            styles.input,
            { backgroundColor: theme.card, borderColor: theme.border, color: theme.text },
          ]}
        />
      </View>

      {error !== null && (
        <Text style={[styles.error, { color: theme.danger }]} accessibilityLiveRegion="polite">
          {error}
        </Text>
      )}

      <FlatList
        data={results}
        keyExtractor={(item) => item.symbol}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={[styles.listContent, { paddingBottom: insets.bottom + 24 }]}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        ListEmptyComponent={
          <Hint
            color={theme.textMuted}
            text={
              searching
                ? ''
                : query.trim().length === 0
                  ? 'Search for a listed company, fund or index — for example Apple, VOD.L or ^FTSE.'
                  : error === null
                    ? 'No matching symbols.'
                    : ''
            }
          />
        }
        renderItem={({ item }) => {
          const alreadyAdded = has(item.symbol);
          const busy = adding === item.symbol;
          return (
            <Pressable
              onPress={() => !alreadyAdded && !busy && onAdd(item.symbol)}
              disabled={alreadyAdded || busy}
              accessibilityRole="button"
              accessibilityState={{ disabled: alreadyAdded, busy }}
              accessibilityLabel={
                `${item.symbol}, ${item.name}` + (alreadyAdded ? ', already on your watchlist' : '')
              }
              style={({ pressed }) => [
                styles.result,
                {
                  backgroundColor: pressed ? theme.cardPressed : theme.card,
                  borderColor: theme.border,
                  opacity: alreadyAdded ? 0.55 : 1,
                },
              ]}
            >
              <View style={styles.resultText}>
                <Text style={[styles.symbol, { color: theme.text }]} numberOfLines={1}>
                  {item.symbol}
                </Text>
                <Text style={[styles.name, { color: theme.textMuted }]} numberOfLines={1}>
                  {item.name}
                </Text>
                <Text style={[styles.meta, { color: theme.textFaint }]} numberOfLines={1}>
                  {[item.exchange, item.type].filter(Boolean).join(' · ')}
                </Text>
              </View>

              {busy ? (
                <ActivityIndicator color={theme.textMuted} />
              ) : (
                <Text style={[styles.action, { color: alreadyAdded ? theme.textFaint : theme.accent }]}>
                  {alreadyAdded ? 'Added' : 'Add'}
                </Text>
              )}
            </Pressable>
          );
        }}
      />

      {searching && (
        <View style={styles.spinner} pointerEvents="none">
          <ActivityIndicator color={theme.textMuted} />
        </View>
      )}
    </View>
  );
}

function Hint({ text, color }: { text: string; color: string }) {
  if (!text) return null;
  return <Text style={[styles.hint, { color }]}>{text}</Text>;
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  searchBar: { paddingHorizontal: 14, paddingTop: 10, paddingBottom: 6 },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  error: { fontSize: 13, paddingHorizontal: 18, paddingBottom: 6 },
  listContent: { paddingHorizontal: 14, paddingTop: 6 },
  separator: { height: 8 },
  result: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 13,
    borderRadius: 13,
    borderWidth: StyleSheet.hairlineWidth,
  },
  resultText: { flex: 1, minWidth: 0 },
  symbol: { fontSize: 16, fontWeight: '700' },
  name: { fontSize: 14, marginTop: 2 },
  meta: { fontSize: 12, marginTop: 3 },
  action: { fontSize: 15, fontWeight: '600' },
  hint: { fontSize: 14, textAlign: 'center', paddingHorizontal: 32, marginTop: 28, lineHeight: 20 },
  spinner: { position: 'absolute', top: 74, alignSelf: 'center' },
});
