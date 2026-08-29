import 'dart:async';

import 'package:flutter/foundation.dart';

import '../background/alert_worker.dart';
import '../models/alert.dart';
import '../models/types.dart';
import '../notifications/notifications.dart';
import 'alert_storage.dart';

/// The user's price alerts, and the scheduling that backs them.
class AlertsModel extends ChangeNotifier {
  AlertsModel({
    AlertStorage? storage,
    AlertNotifier? notifier,
    Future<void> Function(List<PriceAlert>)? scheduler,
  }) : _storage = storage ?? AlertStorage(),
       _notifier = notifier ?? AlertNotifier(),
       // Injected in tests: registering real background work needs a platform.
       _schedule = scheduler ?? syncAlertSchedule;

  final AlertStorage _storage;
  final AlertNotifier _notifier;
  final Future<void> Function(List<PriceAlert>) _schedule;

  List<PriceAlert> _alerts = const [];
  bool _loading = true;
  bool _disposed = false;

  List<PriceAlert> get alerts => List.unmodifiable(_alerts);
  bool get loading => _loading;

  /// Alerts for one symbol, newest first.
  List<PriceAlert> forSymbol(String symbol) => [
    for (final a in _alerts)
      if (a.symbol == symbol) a,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Whether a symbol has at least one armed alert, for the watchlist badge.
  bool hasArmed(String symbol) =>
      _alerts.any((a) => a.symbol == symbol && a.enabled && !a.hasTriggered);

  int get armedCount =>
      _alerts.where((a) => a.enabled && !a.hasTriggered).length;

  Future<void> start() async {
    _alerts = await _storage.load();
    if (_disposed) return;
    _loading = false;
    notifyListeners();
    // Re-assert the schedule on launch: WorkManager registrations do not
    // survive every reinstall or "force stop", and this is cheap.
    unawaited(_schedule(_alerts));
  }

  Future<void> _persist(List<PriceAlert> next) async {
    _alerts = next;
    notifyListeners();
    await _storage.save(next);
    await _schedule(next);
  }

  /// Creates an alert. Returns null on success, or a message explaining why
  /// it was not created.
  Future<String?> add({
    required String symbol,
    required AlertDirection direction,
    required double threshold,
    required String currency,
  }) async {
    if (!threshold.isFinite || threshold <= 0) {
      return 'Enter a price above zero.';
    }

    final duplicate = _alerts.any(
      (a) =>
          a.symbol == symbol &&
          a.direction == direction &&
          a.threshold == threshold &&
          a.enabled &&
          !a.hasTriggered,
    );
    if (duplicate) {
      return 'You already have that alert on $symbol.';
    }

    // Asked for here rather than at launch, so the system prompt arrives with
    // obvious context. A refusal is not fatal — the alert is still recorded,
    // and the user can enable notifications later in system settings.
    await _notifier.requestPermission();

    final now = DateTime.now().millisecondsSinceEpoch;
    await _persist([
      ..._alerts,
      PriceAlert(
        id: '$symbol-$now-${_alerts.length}',
        symbol: symbol,
        direction: direction,
        threshold: threshold,
        currency: currency,
        createdAt: now,
      ),
    ]);
    return null;
  }

  Future<void> remove(String id) => _persist([
    for (final a in _alerts)
      if (a.id != id) a,
  ]);

  Future<void> removeForSymbol(String symbol) => _persist([
    for (final a in _alerts)
      if (a.symbol != symbol) a,
  ]);

  /// Turns an alert on or off. Re-arming a fired alert also clears its
  /// triggered state, so it can fire again.
  Future<void> setEnabled(String id, bool enabled) => _persist([
    for (final a in _alerts)
      if (a.id == id)
        a.copyWith(enabled: enabled, clearTriggered: enabled)
      else
        a,
  ]);

  /// Evaluates alerts against quotes the app just refreshed in the foreground.
  ///
  /// The background worker covers the app being closed; this makes an alert
  /// fire promptly when the user happens to have the app open, rather than
  /// waiting up to 15 minutes for the next background pass.
  Future<void> evaluateAgainst(Map<String, Quote> quotes) async {
    if (_alerts.isEmpty) return;

    final prices = {for (final e in quotes.entries) e.key: e.value.price};
    final fired = firedAlerts(_alerts, prices);
    if (fired.isEmpty) return;

    for (final alert in fired) {
      await _notifier.showAlert(alert, prices[alert.symbol]!);
    }

    final firedIds = {for (final a in fired) a.id};
    final now = DateTime.now().millisecondsSinceEpoch;
    await _persist([
      for (final a in _alerts)
        if (firedIds.contains(a.id))
          a.copyWith(enabled: false, triggeredAt: now)
        else
          a,
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
