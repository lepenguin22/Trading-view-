import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/alert.dart';
import '../utils/format.dart';

const _channelId = 'price_alerts';
const _channelName = 'Price alerts';
const _channelDescription =
    'Fires when a symbol on your watchlist crosses a price you set.';

/// Wrapper over the local notification plugin.
///
/// Initialised in two places — the app on startup, and the background worker
/// in its own isolate — so [ensureInitialized] is idempotent per isolate.
class AlertNotifier {
  AlertNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        // The launcher icon; the plugin requires a drawable that exists.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for explicitly on first alert instead, so the prompt has
          // context rather than appearing on a cold first launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  /// Asks for notification permission, returning whether it was granted.
  ///
  /// Called when the user creates their first alert rather than at launch:
  /// Android 13+ and iOS both show a system prompt, and it is far likelier to
  /// be granted when the user has just asked for the thing it enables.
  Future<bool> requestPermission() async {
    await ensureInitialized();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  /// Posts the notification for an alert that has just fired.
  Future<void> showAlert(PriceAlert alert, double price) async {
    await ensureInitialized();

    final now = formatPrice(price, alert.currency);

    await _plugin.show(
      id: notificationIdFor(alert),
      // A crossover can fire on a symbol whose quote request failed, so the
      // price is not always known. The condition itself always is.
      title: price > 0 ? '${alert.symbol} is at $now' : '${alert.symbol} alert',
      body: '${alert.describe((v) => formatPrice(v, alert.currency))}.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: alert.symbol,
    );
  }
}

/// A stable notification id for an alert.
///
/// Android notification ids are 32-bit signed, so the string id is folded down
/// rather than used directly.
int notificationIdFor(PriceAlert alert) => alert.id.hashCode & 0x7FFFFFFF;
