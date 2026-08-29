import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/types.dart';

const _symbolsKey = 'ticker.watchlist.symbols.v1';
const _quotesKey = 'ticker.watchlist.quotes.v1';

/// Shown on first launch so the app is not an empty screen.
const defaultSymbols = <String>['AAPL', 'MSFT', 'NVDA', 'AMZN'];

/// Persistence for the watchlist.
///
/// Storage is best-effort: a read failure means the watchlist starts from the
/// defaults, and a write failure means this change is not carried across a
/// relaunch. Neither is worth interrupting the user for, so both are
/// swallowed.
class WatchlistStorage {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<String>> loadSymbols() async {
    try {
      final raw = (await _prefs).getString(_symbolsKey);
      if (raw == null) return List.of(defaultSymbols);
      final parsed = jsonDecode(raw);
      if (parsed is! List) return List.of(defaultSymbols);
      return parsed
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return List.of(defaultSymbols);
    }
  }

  Future<void> saveSymbols(List<String> symbols) async {
    try {
      await (await _prefs).setString(_symbolsKey, jsonEncode(symbols));
    } catch (_) {
      // Ignore: the in-memory watchlist is still correct for this session.
    }
  }

  /// Quotes are cached only so a cold start shows prices immediately instead
  /// of empty rows. They are always refreshed on launch, and the UI marks them
  /// stale if that refresh fails.
  Future<Map<String, Quote>> loadCachedQuotes() async {
    try {
      final raw = (await _prefs).getString(_quotesKey);
      if (raw == null) return {};
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return {};

      final out = <String, Quote>{};
      parsed.forEach((key, value) {
        if (key is! String || value is! Map) return;
        try {
          out[key] = Quote.fromJson(value.cast<String, dynamic>());
        } catch (_) {
          // Drop a single unreadable entry rather than the whole cache: the
          // stored shape may predate a change to Quote.
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCachedQuotes(Map<String, Quote> quotes) async {
    try {
      final encodable = quotes.map((k, v) => MapEntry(k, v.toJson()));
      await (await _prefs).setString(_quotesKey, jsonEncode(encodable));
    } catch (_) {
      // Ignore: caching is an optimisation, not a correctness requirement.
    }
  }
}
