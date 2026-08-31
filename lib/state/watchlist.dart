import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/yahoo.dart';
import '../models/types.dart';
import '../utils/format.dart';
import 'refresh_policy.dart';
import 'storage.dart';

/// What a portfolio import did.
///
/// An import mirrors the sheet, so it can remove as well as add. The screen
/// reports both rather than a bare success, because a removal the user did not
/// expect is the thing they most need to see.
class ImportOutcome {
  const ImportOutcome({
    required this.added,
    required this.removed,
    required this.unchanged,
    required this.failed,
  });

  /// In the sheet, not previously in the portfolio.
  final List<String> added;

  /// Previously in the portfolio, no longer in the sheet.
  final List<String> removed;

  final List<String> unchanged;

  /// Symbol to the reason the price feed rejected it. These are still kept in
  /// the portfolio — the sheet is the source of truth for what is held, and
  /// dropping a holding because a request failed would be worse than showing
  /// it with an error.
  final Map<String, String> failed;

  bool get changedNothing => added.isEmpty && removed.isEmpty;
}

/// The watchlist: which symbols the user tracks, their latest quotes, and the
/// polling that keeps those quotes current.
///
/// Polling runs only while the app is on screen — refreshing in the background
/// would burn battery for a screen nobody is looking at.
class WatchlistModel extends ChangeNotifier with WidgetsBindingObserver {
  WatchlistModel({YahooApi? api, WatchlistStorage? storage})
    : _api = api ?? YahooApi(),
      // An API handed in from outside outlives this model, so closing it here
      // would break the screens still sharing it.
      _ownsApi = api == null,
      _storage = storage ?? WatchlistStorage();

  final YahooApi _api;
  final bool _ownsApi;
  final WatchlistStorage _storage;

  List<String> _symbols = const [];
  List<String> _portfolio = const [];
  Map<String, Quote> _quotes = const {};
  Map<String, String> _errors = const {};
  bool _hydrating = true;
  bool _refreshing = false;
  int? _lastUpdated;

  Timer? _timer;
  CancelToken? _inFlight;

  /// The symbol whose detail screen is open, polled faster than the lists.
  String? _focusSymbol;

  /// How long since each kind of refresh last completed, so the policy can
  /// decide what a tick owes without a timer per concern.
  ///
  /// Accumulated a tick at a time rather than read off the wall clock: the
  /// timer only runs in the foreground, and a resume forces a full refresh
  /// that zeroes both, so ticks are the only elapsed time that matters.
  Duration _sinceList = Duration.zero;
  Duration _sinceFocus = Duration.zero;
  bool _refreshingOne = false;
  bool _disposed = false;

  /// Called with the full quote map after every refresh that returned data.
  ///
  /// Set by the app so price alerts can be evaluated the moment a foreground
  /// refresh lands, instead of waiting for the next background check.
  Future<void> Function(Map<String, Quote>)? onQuotes;

  /// Watchlist order, as the user arranged it.
  List<String> get symbols => List.unmodifiable(_symbols);

  /// Holdings imported from a spreadsheet, kept apart from the watchlist.
  List<String> get portfolio => List.unmodifiable(_portfolio);

  /// Every symbol needing a quote. Both lists are polled together and share
  /// one quote map, so a symbol on both is fetched once.
  List<String> get _tracked => {..._symbols, ..._portfolio}.toList();

  Map<String, Quote> get quotes => Map.unmodifiable(_quotes);

  /// Per-symbol failure messages from the last refresh.
  Map<String, String> get errors => Map.unmodifiable(_errors);

  /// True until the persisted watchlist has been read.
  bool get hydrating => _hydrating;

  bool get refreshing => _refreshing;

  /// Epoch ms of the last refresh that returned at least one quote.
  int? get lastUpdated => _lastUpdated;

  bool has(String symbol) => _symbols.contains(normaliseSymbol(symbol));

  bool isInPortfolio(String symbol) =>
      _portfolio.contains(normaliseSymbol(symbol));

  /// Reads the persisted watchlist and cached quotes, then does a first
  /// refresh and starts polling.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);

    final saved = await _storage.loadSymbols();
    final cached = await _storage.loadCachedQuotes();
    if (_disposed) return;

    _symbols = saved;
    _portfolio = await _storage.loadPortfolio();
    _quotes = cached;
    _hydrating = false;
    notifyListeners();

    _startPolling();
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      unawaited(refresh());
    } else {
      _stopPolling();
    }
  }

  /// True when any tracked symbol's market is open, from the last quotes seen.
  bool get marketOpen =>
      isMarketOpen([for (final q in _quotes.values) q.marketState]);

  /// Marks a symbol as the one on screen, so it is polled quickly.
  void focusOn(String symbol) {
    if (_focusSymbol == symbol) return;
    _focusSymbol = symbol;
    // Due immediately, so the first fast poll happens on the next tick rather
    // than up to a whole interval after the screen opened.
    _sinceFocus = focusInterval;
  }

  void clearFocus(String symbol) {
    if (_focusSymbol == symbol) _focusSymbol = null;
  }

  void _startPolling() {
    _timer ??= Timer.periodic(refreshTick, (_) => unawaited(_onTick()));
  }

  /// Runs whatever the policy says this tick owes.
  Future<void> _onTick() async {
    _sinceList += refreshTick;
    _sinceFocus += refreshTick;

    final plan = planRefresh(
      sinceList: _sinceList,
      sinceFocus: _sinceFocus,
      focusSymbol: _focusSymbol,
      marketOpen: marketOpen,
    );

    if (plan.refreshList) return refresh();
    final symbol = plan.refreshSymbol;
    if (symbol != null) return refreshOne(symbol);
  }

  /// Refetches a single symbol.
  ///
  /// Separate from [refresh] so watching one stock costs one request per tick
  /// rather than one per holding.
  Future<void> refreshOne(String symbol) async {
    if (_refreshingOne || _disposed) return;
    _refreshingOne = true;
    try {
      final quote = await _api.fetchQuote(symbol);
      if (_disposed) return;
      final next = Map.of(_quotes)..[quote.symbol] = quote;
      _quotes = next;
      _errors = Map.of(_errors)..remove(symbol);
      _lastUpdated = DateTime.now().millisecondsSinceEpoch;
      _sinceFocus = Duration.zero;
      unawaited(_storage.saveCachedQuotes(next));
      unawaited(_notifyQuoteListeners(next));
      notifyListeners();
    } catch (err) {
      if (_disposed) return;
      // A single failed tick is not worth surfacing: the next one, or the
      // whole-list refresh behind it, will correct it.
      _sinceFocus = Duration.zero;
      debugPrint('Focused refresh of $symbol failed: $err');
    } finally {
      _refreshingOne = false;
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Re-fetches every symbol on the list. Superseded by a later call: an
  /// in-flight refresh is abandoned rather than allowed to overwrite fresher
  /// data with staler.
  Future<void> refresh() async {
    final list = _tracked;
    if (list.isEmpty) {
      if (_errors.isNotEmpty) {
        _errors = const {};
        notifyListeners();
      }
      return;
    }

    _inFlight?.cancel();
    final token = CancelToken();
    _inFlight = token;

    _refreshing = true;
    notifyListeners();

    try {
      final batch = await _api.fetchQuotes(list, token: token);
      if (token.isCancelled || _disposed) return;

      if (batch.quotes.isNotEmpty) {
        final next = Map.of(_quotes);
        for (final q in batch.quotes) {
          next[q.symbol] = q;
        }
        _quotes = next;
        _lastUpdated = DateTime.now().millisecondsSinceEpoch;
        unawaited(_storage.saveCachedQuotes(next));
        unawaited(_notifyQuoteListeners(next));
      }
      _errors = batch.errors;
    } finally {
      if (!token.isCancelled && !_disposed) {
        _sinceList = Duration.zero;
        // A whole-list refresh covers the focused symbol, so its clock resets
        // too and the two do not double up.
        _sinceFocus = Duration.zero;
        _refreshing = false;
        if (identical(_inFlight, token)) _inFlight = null;
        notifyListeners();
      }
    }
  }

  /// Alert evaluation must never take the refresh down with it: a failure
  /// here means no notification, not a broken watchlist.
  Future<void> _notifyQuoteListeners(Map<String, Quote> quotes) async {
    try {
      await onQuotes?.call(quotes);
    } catch (error, stack) {
      debugPrint('Alert evaluation failed: $error\n$stack');
    }
  }

  void _persist(List<String> next) {
    _symbols = next;
    unawaited(_storage.saveSymbols(next));
    notifyListeners();
  }

  /// Adds a symbol to the watchlist.
  ///
  /// Returns null on success, or a message explaining why it was not added.
  /// The quote is fetched before the symbol is committed, so a typo never
  /// lands a dead row on the list.
  Future<String?> addSymbol(String input) async {
    final symbol = normaliseSymbol(input);
    if (symbol.isEmpty) return 'Enter a ticker symbol.';
    if (_symbols.contains(symbol)) {
      return '$symbol is already on your watchlist.';
    }

    try {
      final quote = await _api.fetchQuote(symbol);
      if (_disposed) return null;

      final next = Map.of(_quotes)..[quote.symbol] = quote;
      _quotes = next;
      _lastUpdated = DateTime.now().millisecondsSinceEpoch;
      unawaited(_storage.saveCachedQuotes(next));
      _persist([..._symbols, quote.symbol]);
      return null;
    } catch (err) {
      return describeError(err);
    }
  }

  /// Replaces the portfolio with what the sheet says.
  ///
  /// This mirrors rather than merges: a holding sold and deleted from the
  /// sheet disappears here on the next import. Only ever called with a sheet
  /// that fetched and parsed successfully, so a network failure can never
  /// empty the list.
  ///
  /// Symbols the price feed rejects are kept, not dropped. The sheet is the
  /// authority on what is held, and removing a holding because one request
  /// failed would be worse than showing it with an error; the failures are
  /// reported so the sheet can be corrected.
  Future<ImportOutcome> importPortfolio(List<String> symbols) async {
    final next = <String>[];
    for (final raw in symbols) {
      final symbol = normaliseSymbol(raw);
      if (symbol.isNotEmpty && !next.contains(symbol)) next.add(symbol);
    }

    final previous = _portfolio;
    final outcome = ImportOutcome(
      added: [
        for (final s in next)
          if (!previous.contains(s)) s,
      ],
      removed: [
        for (final s in previous)
          if (!next.contains(s)) s,
      ],
      unchanged: [
        for (final s in next)
          if (previous.contains(s)) s,
      ],
      failed: const {},
    );

    _portfolio = next;
    notifyListeners();
    await _storage.savePortfolio(next);

    // Price whatever is not already known, so the rows fill in immediately
    // rather than waiting for the next poll.
    final unpriced = [
      for (final s in next)
        if (!_quotes.containsKey(s)) s,
    ];
    if (unpriced.isEmpty || _disposed) return outcome;

    final batch = await _api.fetchQuotes(unpriced);
    if (_disposed) return outcome;

    if (batch.quotes.isNotEmpty) {
      final quotes = Map.of(_quotes);
      for (final q in batch.quotes) {
        quotes[q.symbol] = q;
      }
      _quotes = quotes;
      _lastUpdated = DateTime.now().millisecondsSinceEpoch;
      unawaited(_storage.saveCachedQuotes(quotes));
    }
    if (batch.errors.isNotEmpty) {
      _errors = {..._errors, ...batch.errors};
    }
    notifyListeners();

    return ImportOutcome(
      added: outcome.added,
      removed: outcome.removed,
      unchanged: outcome.unchanged,
      failed: batch.errors,
    );
  }

  /// Drops one holding from the portfolio.
  ///
  /// A convenience for hiding something now; the sheet still decides, so it
  /// returns on the next import unless it is deleted there too.
  void removeFromPortfolio(String symbol) {
    final next = _portfolio.where((s) => s != symbol).toList(growable: false);
    if (next.length == _portfolio.length) return;
    _portfolio = next;
    notifyListeners();
    unawaited(_storage.savePortfolio(next));
  }

  void removeSymbol(String symbol) {
    _errors = Map.of(_errors)..remove(symbol);
    _persist(_symbols.where((s) => s != symbol).toList(growable: false));
  }

  /// Nudges a symbol one place up (-1) or down (1); a no-op at either end.
  void moveSymbol(String symbol, int direction) {
    final from = _symbols.indexOf(symbol);
    final to = from + direction;
    if (from == -1 || to < 0 || to >= _symbols.length) return;
    final next = List.of(_symbols);
    next[from] = _symbols[to];
    next[to] = symbol;
    _persist(next);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _inFlight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsApi) _api.dispose();
    super.dispose();
  }
}
