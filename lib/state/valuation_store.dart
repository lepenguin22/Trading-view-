import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/valuation_source.dart';
import '../api/yahoo.dart' show describeError;
import '../models/valuation.dart';

const _apiKeyKey = 'ticker.valuation.apiKey.v1';
const _cacheKey = 'ticker.valuation.cache.v1';

/// Fair values, their cache, and the API key that fetches them.
///
/// Fetching is lazy and per symbol: a DCF is only requested when a detail
/// screen asks for one and the cached copy has expired. It is deliberately not
/// part of the 60-second price poll — that would spend a few hundred free
/// requests a day on a figure that moves quarterly.
class ValuationModel extends ChangeNotifier {
  ValuationModel({ValuationSource? source})
    : _source = source ?? ValuationSource();

  final ValuationSource _source;

  String _apiKey = '';
  Map<String, Valuation> _cache = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  bool _disposed = false;

  /// Completes when the key and cache have been read.
  ///
  /// Every fetch waits on this. Without it a screen opened in the first
  /// moments after launch asks for a valuation before the key has loaded,
  /// finds none, and gives up silently — leaving the section blank until the
  /// user happens to navigate away and back.
  Future<void>? _ready;

  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  String get apiKey => _apiKey;

  Valuation? valuationFor(String symbol) => _cache[symbol];
  String? errorFor(String symbol) => _errors[symbol];
  bool isLoading(String symbol) => _loading.contains(symbol);

  Future<void> start() {
    return _ready ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _apiKey = prefs.getString(_apiKeyKey) ?? '';

      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          final out = <String, Valuation>{};
          parsed.forEach((key, value) {
            if (key is! String || value is! Map) return;
            try {
              out[key] = Valuation.fromJson(value.cast<String, dynamic>());
            } catch (_) {
              // Drop one unreadable entry rather than the whole cache.
            }
          });
          _cache = out;
        }
      }
    } catch (_) {
      // A cache that will not load is not worth interrupting launch for.
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    // Errors are mostly "key rejected"; a new key deserves a fresh attempt.
    _errors.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiKeyKey, _apiKey);
    } catch (_) {
      // Ignore: the key still works for this session.
    }
  }

  /// Fetches [symbol] unless a fresh copy is cached.
  ///
  /// Safe to call on every detail-screen open: a cache hit does nothing, and
  /// a request already in flight is not duplicated.
  Future<void> ensureLoaded(String symbol, {bool force = false}) async {
    // Hydration may still be in flight; joining it is what makes this safe to
    // call from a screen that opened moments after launch.
    await start();
    if (_disposed) return;

    if (!hasApiKey || _loading.contains(symbol)) return;

    final cached = _cache[symbol];
    if (!force && cached != null && !isStale(cached)) return;

    _loading.add(symbol);
    _errors.remove(symbol);
    notifyListeners();

    try {
      final valuation = await _source.fetch(symbol, _apiKey);
      if (_disposed) return;
      _cache = {..._cache, symbol: valuation};
      unawaited(_persistCache());
    } catch (err) {
      if (_disposed) return;
      _errors[symbol] = describeError(err);
    } finally {
      if (!_disposed) {
        _loading.remove(symbol);
        notifyListeners();
      }
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(_cache.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {
      // Caching is an optimisation, not a correctness requirement.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _source.dispose();
    super.dispose();
  }
}
