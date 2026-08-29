import 'dart:ui' show DartPluginRegistrant;

import 'package:workmanager/workmanager.dart';

import '../api/yahoo.dart';
import '../models/alert.dart';
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

  final client = api ?? YahooApi();
  final Map<String, double> prices;
  try {
    final batch = await client.fetchQuotes(symbols.toList(growable: false));
    prices = {for (final q in batch.quotes) q.symbol: q.price};
  } finally {
    if (api == null) client.dispose();
  }

  if (prices.isEmpty) return const [];

  final fired = firedAlerts(alerts, prices);
  if (fired.isEmpty) return const [];

  final alerter = notifier ?? AlertNotifier();
  for (final alert in fired) {
    await alerter.showAlert(alert, prices[alert.symbol]!);
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
