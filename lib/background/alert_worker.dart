import 'dart:ui' show DartPluginRegistrant;

import 'package:workmanager/workmanager.dart';

import 'package:flutter/foundation.dart';

import '../api/yahoo.dart';
import '../models/alert.dart';
import '../models/crossover.dart';
import '../utils/indicators.dart';
import '../notifications/notifications.dart';
import '../state/alert_storage.dart';

/// Unique name of the periodic work registration.
const alertTaskUniqueName = 'ticker.price-alerts';

/// Task name handed to the dispatcher.
const alertTaskName = 'checkPriceAlerts';

/// Android's WorkManager will not run periodic work more often than this, so
/// asking for less just gets silently clamped.
const alertCheckInterval = Duration(minutes: 15);

/// Entry point for the background isolate.
///
/// Must be a top-level function annotated for AOT retention, or the tree
/// shaker removes it and the task fails silently in release builds.
@pragma('vm:entry-point')
void alertCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != alertTaskName) return true;
    // The isolate starts without the plugin registry the app sets up, so
    // plugins must be registered before any of them are touched.
    DartPluginRegistrant.ensureInitialized();
    await runAlertCheck();
    return true;
  });
}

/// Fetches prices for every armed alert and fires the ones that are met.
///
/// Returns the alerts that fired. Safe to call from either isolate: it
/// re-reads storage immediately before writing, so a concurrent edit from the
/// UI is not clobbered by a worker holding a stale list.
Future<List<PriceAlert>> runAlertCheck({
  YahooApi? api,
  AlertStorage? storage,
  AlertNotifier? notifier,
}) async {
  final store = storage ?? AlertStorage();
  final alerts = await store.load();
  final symbols = symbolsToWatch(alerts);
  if (symbols.isEmpty) return const [];

  final needHistory = symbolsNeedingHistory(alerts);

  final client = api ?? YahooApi();
  final Map<String, AlertInputs> inputs;
  try {
    final batch = await client.fetchQuotes(symbols.toList(growable: false));
    final prices = {for (final q in batch.quotes) q.symbol: q.price};

    final indicators = await _indicatorsFor(client, needHistory);

    inputs = {
      for (final symbol in {...prices.keys, ...indicators.keys})
        symbol: AlertInputs(
          price: prices[symbol],
          rsi: indicators[symbol]?.rsi,
          crossings: indicators[symbol]?.crossings ?? const [],
        ),
    };
  } finally {
    if (api == null) client.dispose();
  }

  if (inputs.isEmpty) return const [];

  final fired = firedAlerts(alerts, inputs);
  if (fired.isEmpty) return const [];

  final alerter = notifier ?? AlertNotifier();
  for (final alert in fired) {
    // A crossover alert may fire on a symbol whose quote request failed, so
    // the price is not guaranteed. Zero is only ever a display fallback here;
    // the alert's own condition has already been decided.
    await alerter.showAlert(alert, inputs[alert.symbol]?.price ?? 0);
  }

  // Re-read rather than writing back the list loaded above: the user may have
  // added or deleted an alert while the fetch was in flight.
  final firedIds = {for (final a in fired) a.id};
  final now = DateTime.now().millisecondsSinceEpoch;
  final latest = await store.load();
  await store.save([
    for (final a in latest)
      if (firedIds.contains(a.id))
        a.copyWith(enabled: false, triggeredAt: now)
      else
        a,
  ]);

  return fired;
}

/// What one symbol's daily history says about its indicators.
typedef _Indicators = ({double? rsi, List<CrossingEvent> crossings});

/// Fetches daily history for [symbols] and derives their indicators.
///
/// Only called with the symbols that actually carry an indicator alert, so a
/// list of plain price alerts never pays for history. A symbol whose history
/// fails is simply absent, which reads as "not known" rather than "condition
/// not met".
Future<Map<String, _Indicators>> _indicatorsFor(
  YahooApi client,
  Set<String> symbols,
) async {
  if (symbols.isEmpty) return const {};

  final out = <String, _Indicators>{};
  await Future.wait(
    symbols.map((symbol) async {
      try {
        final history = await client.fetchHistory(symbol);
        final closes = history.closes;
        if (closes.isEmpty) return;

        final rsiSeries = relativeStrengthIndex(closes, rsiPeriod);
        final movingAverages = {
          for (final period in maPeriods)
            period: simpleMovingAverage(closes, period),
        };

        final crossings = <CrossingEvent>[];
        for (final spec in crossoverSpecs) {
          for (final cross in crossingsFor(
            spec,
            closes: closes,
            movingAverages: movingAverages,
          )) {
            if (cross.index >= history.candles.length) continue;
            crossings.add((
              crossoverId: spec.id,
              direction: cross.direction,
              at: history.candles[cross.index].t * 1000,
            ));
          }
        }

        out[symbol] = (
          rsi: rsiSeries.lastWhere((v) => v != null, orElse: () => null),
          crossings: crossings,
        );
      } catch (error) {
        // One symbol's history failing must not take the whole check down:
        // the other alerts still deserve to be evaluated.
        debugPrint('History for $symbol unavailable: $error');
      }
    }),
  );
  return out;
}

/// Schedules the periodic check, or cancels it when nothing is armed.
///
/// Called whenever the alert list changes, so a device with no live alerts
/// does no background work at all.
Future<void> syncAlertSchedule(List<PriceAlert> alerts) async {
  if (symbolsToWatch(alerts).isEmpty) {
    await Workmanager().cancelByUniqueName(alertTaskUniqueName);
    return;
  }

  await Workmanager().registerPeriodicTask(
    alertTaskUniqueName,
    alertTaskName,
    frequency: alertCheckInterval,
    // Prices cannot be checked without a network, and retrying offline just
    // burns battery.
    constraints: Constraints(networkType: NetworkType.connected),
    // `update` keeps the existing schedule's timing instead of restarting the
    // interval every time the user edits an alert.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
