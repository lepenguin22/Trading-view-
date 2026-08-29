import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/models/alert.dart';
import 'package:ticker/state/alert_storage.dart';

PriceAlert alert({
  String id = 'a1',
  String symbol = 'AAPL',
  AlertDirection direction = AlertDirection.above,
  double threshold = 200,
  bool enabled = true,
  int? triggeredAt,
}) => PriceAlert(
  id: id,
  symbol: symbol,
  direction: direction,
  threshold: threshold,
  currency: 'USD',
  createdAt: 1000,
  enabled: enabled,
  triggeredAt: triggeredAt,
);

void main() {
  group('PriceAlert.isMet', () {
    test('an above alert fires at or past the threshold', () {
      final a = alert(direction: AlertDirection.above, threshold: 200);
      expect(a.isMet(199.99), isFalse);
      expect(a.isMet(200), isTrue);
      expect(a.isMet(250), isTrue);
    });

    test('a below alert fires at or under the threshold', () {
      final a = alert(direction: AlertDirection.below, threshold: 150);
      expect(a.isMet(150.01), isFalse);
      expect(a.isMet(150), isTrue);
      expect(a.isMet(10), isTrue);
    });

    test('never fires on a non-finite price', () {
      // A malformed payload must not be read as a threshold crossing.
      expect(alert().isMet(double.nan), isFalse);
      expect(alert().isMet(double.infinity), isFalse);
    });
  });

  group('firedAlerts', () {
    test('returns only the alerts their symbol price satisfies', () {
      final alerts = [
        alert(id: 'a', symbol: 'AAPL', threshold: 200),
        alert(id: 'b', symbol: 'MSFT', threshold: 500),
      ];
      final fired = firedAlerts(alerts, {'AAPL': 210, 'MSFT': 400});
      expect(fired.map((a) => a.id), ['a']);
    });

    test('skips disabled and already-triggered alerts', () {
      final alerts = [
        alert(id: 'off', threshold: 100, enabled: false),
        alert(id: 'done', threshold: 100, triggeredAt: 5),
        alert(id: 'live', threshold: 100),
      ];
      expect(firedAlerts(alerts, {'AAPL': 250}).map((a) => a.id), ['live']);
    });

    test('skips a symbol with no price rather than treating it as unmet', () {
      // A failed fetch must not silently count as "the condition did not hold".
      final fired = firedAlerts([alert(threshold: 1)], const {});
      expect(fired, isEmpty);
    });
  });

  group('symbolsToWatch', () {
    test('collects distinct armed symbols only', () {
      final alerts = [
        alert(id: 'a', symbol: 'AAPL'),
        alert(id: 'b', symbol: 'AAPL', threshold: 300),
        alert(id: 'c', symbol: 'MSFT', enabled: false),
        alert(id: 'd', symbol: 'NVDA', triggeredAt: 9),
      ];
      expect(symbolsToWatch(alerts), {'AAPL'});
    });

    test('is empty when nothing is armed', () {
      expect(symbolsToWatch([alert(enabled: false)]), isEmpty);
    });
  });

  group('copyWith', () {
    test('re-arming clears the triggered timestamp', () {
      final fired = alert(enabled: false, triggeredAt: 42);
      final rearmed = fired.copyWith(enabled: true, clearTriggered: true);
      expect(rearmed.enabled, isTrue);
      expect(rearmed.hasTriggered, isFalse);
    });

    test('disarming on fire keeps the timestamp', () {
      final fired = alert().copyWith(enabled: false, triggeredAt: 99);
      expect(fired.enabled, isFalse);
      expect(fired.triggeredAt, 99);
    });
  });

  group('AlertStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips alerts through storage', () async {
      final storage = AlertStorage();
      final original = [
        alert(id: 'a', direction: AlertDirection.below, threshold: 12.5),
        alert(id: 'b', triggeredAt: 77, enabled: false),
      ];
      await storage.save(original);

      final loaded = await storage.load();
      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'a');
      expect(loaded[0].direction, AlertDirection.below);
      expect(loaded[0].threshold, 12.5);
      expect(loaded[1].triggeredAt, 77);
      expect(loaded[1].enabled, isFalse);
    });

    test('returns an empty list when nothing is stored', () async {
      expect(await AlertStorage().load(), isEmpty);
    });

    test('drops an unreadable entry rather than the whole list', () async {
      SharedPreferences.setMockInitialValues({
        'ticker.alerts.v1':
            '[{"id":"ok","symbol":"AAPL","direction":"above","threshold":1,'
            '"currency":"USD","createdAt":1,"enabled":true},{"bogus":true}]',
      });
      final loaded = await AlertStorage().load();
      expect(loaded.map((a) => a.id), ['ok']);
    });
  });
}
