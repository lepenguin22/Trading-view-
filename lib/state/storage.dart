import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/holding.dart';
import '../models/types.dart';

const _symbolsKey = 'ticker.watchlist.symbols.v1';
const _sheetUrlKey = 'ticker.portfolio.sheetUrl.v1';
const _portfolioKey = 'ticker.portfolio.symbols.v1';
const _holdingsKey = 'ticker.portfolio.holdings.v1';
const _quotesKey = 'ticker.watchlist.quotes.v1';

/// Written by the removed fair-value feature. Purged on launch: the first is
/// an API key, and leaving a credential in app storage with no screen left to
/// clear it from would be worse than the feature was useful.
const _obsoleteKeys = <String>[
  'ticker.valuation.apiKey.v1',
  'ticker.valuation.cache.v1',
];

/// Drops storage left behind by features that no longer exist.
///
/// Best-effort and silent, like every other write here: a failure means the
/// stale entries survive until the next launch, which is not worth
/// interrupting a launch for.
Future<void> purgeObsoleteStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _obsoleteKeys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  } catch (_) {
    // Ignored deliberately.
  }
}

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

  /// The imported portfolio. Kept separate from the watchlist: one is what the
  /// user chose to follow, the other is what a spreadsheet says they own, and
  /// an import rewrites the second without touching the first.
  /// Reads the portfolio, falling back to the symbols-only key an older
  /// install wrote.
  ///
  /// The fallback matters: a portfolio was a bare list of symbols before
  /// quantities existed, and reading only the new key would silently empty the
  /// list of anyone upgrading. Those holdings come back with no share count,
  /// which is exactly true of them until the sheet is imported again.
  Future<List<Holding>> loadPortfolio() async {
    try {
      final prefs = await _prefs;

      final raw = prefs.getString(_holdingsKey);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is! List) return const [];
        return [for (final entry in parsed) ?Holding.fromJson(entry)];
      }

      final legacy = prefs.getString(_portfolioKey);
      if (legacy == null) return const [];
      final parsed = jsonDecode(legacy);
      if (parsed is! List) return const [];
      return [
        for (final symbol in parsed.whereType<String>())
          if (symbol.isNotEmpty) Holding(symbol: symbol),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePortfolio(List<Holding> holdings) async {
    try {
      final prefs = await _prefs;
      await prefs.setString(
        _holdingsKey,
        jsonEncode([for (final h in holdings) h.toJson()]),
      );
      // The old key is kept in step rather than deleted, so downgrading to a
      // build without quantities still finds a portfolio.
      await prefs.setString(
        _portfolioKey,
        jsonEncode([for (final h in holdings) h.symbol]),
      );
    } catch (_) {
      // Ignore: the in-memory list is still correct for this session.
    }
  }

  /// The last portfolio sheet URL, so re-importing is one tap rather than a
  /// paste. Only the URL is kept — no account is linked and no token stored.
  Future<String?> loadSheetUrl() async {
    try {
      return (await _prefs).getString(_sheetUrlKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSheetUrl(String url) async {
    try {
      await (await _prefs).setString(_sheetUrlKey, url);
    } catch (_) {
      // Ignore: the import still worked, it just will not be remembered.
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
