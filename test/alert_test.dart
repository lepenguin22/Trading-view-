import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/models/alert.dart';
import 'package:ticker/state/alert_storage.dart';
import 'package:ticker/utils/indicators.dart';

PriceAlert alert({
  String id = 'a1',
  String symbol = 'AAPL',
  AlertDirection direction = AlertDirection.above,
  double threshold = 200,
  bool enabled = true,
  int? triggeredAt,
  AlertKind kind = AlertKind.price,
  String? crossoverId,
  int createdAt = 1000,
}) => PriceAlert(
  id: id,
  symbol: symbol,
  kind: kind,
  crossoverId: crossoverId,
  direction: direction,
  threshold: threshold,
  currency: 'USD',
  createdAt: createdAt,
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
      final fired = firedAlerts(
        alerts,
        priceInputs({'AAPL': 210, 'MSFT': 400}),
      );
      expect(fired.map((a) => a.id), ['a']);
    });

    test('skips disabled and already-triggered alerts', () {
      final alerts = [
        alert(id: 'off', threshold: 100, enabled: false),
        alert(id: 'done', threshold: 100, triggeredAt: 5),
        alert(id: 'live', threshold: 100),
      ];
      expect(firedAlerts(alerts, priceInputs({'AAPL': 250})).map((a) => a.id), [
        'live',
      ]);
    });

    test('skips a symbol with no price rather than treating it as unmet', () {
      // A failed fetch must not silently count as "the condition did not hold".
      final fired = firedAlerts([alert(threshold: 1)], const {});
      expect(fired, isEmpty);
    });
  });

  group('RSI alerts', () {
    test('fires when RSI reaches the level, either side', () {
      final oversold = alert(
        kind: AlertKind.rsi,
        direction: AlertDirection.below,
        threshold: 30,
      );
      final overbought = alert(
        kind: AlertKind.rsi,
        direction: AlertDirection.above,
        threshold: 70,
      );

      expect(oversold.isMetBy(const AlertInputs(rsi: 22)), isTrue);
      expect(oversold.isMetBy(const AlertInputs(rsi: 45)), isFalse);
      expect(overbought.isMetBy(const AlertInputs(rsi: 81)), isTrue);
      expect(overbought.isMetBy(const AlertInputs(rsi: 45)), isFalse);
    });

    test('an unknown RSI never fires, price alone is not enough', () {
      // A quote carries no history, so RSI is unknown in the foreground. That
      // must read as "not known", never as "condition met".
      final a = alert(
        kind: AlertKind.rsi,
        direction: AlertDirection.below,
        threshold: 30,
      );

      expect(a.isMetBy(const AlertInputs(price: 1)), isFalse);
      expect(a.isMetBy(const AlertInputs()), isFalse);
    });

    test('a price alert is unaffected by RSI being present', () {
      final a = alert(threshold: 200);

      expect(a.isMetBy(const AlertInputs(price: 210, rsi: 5)), isTrue);
      expect(a.isMetBy(const AlertInputs(price: 190, rsi: 95)), isFalse);
    });
  });

  group('crossover alerts', () {
    CrossingEvent event(String id, CrossDirection direction, int at) =>
        (crossoverId: id, direction: direction, at: at);

    PriceAlert goldenCross({int createdAt = 1000}) => alert(
      kind: AlertKind.crossover,
      crossoverId: 'ma50x200',
      direction: AlertDirection.above,
      createdAt: createdAt,
    );

    test('fires on a crossing dated after the alert was created', () {
      final a = goldenCross(createdAt: 1000);

      expect(
        a.isMetBy(
          AlertInputs(crossings: [event('ma50x200', CrossDirection.up, 2000)]),
        ),
        isTrue,
      );
    });

    test('does not fire on a crossing from before it was created', () {
      // Creating a Golden Cross alert must not fire on last month's cross.
      final a = goldenCross(createdAt: 5000);

      expect(
        a.isMetBy(
          AlertInputs(crossings: [event('ma50x200', CrossDirection.up, 1000)]),
        ),
        isFalse,
      );
    });

    test('fires on a crossing that happened while the phone was off', () {
      // Dated by the bar, not by when the check ran, so a missed day is not a
      // missed alert.
      final a = goldenCross(createdAt: 1000);

      expect(
        a.isMetBy(
          AlertInputs(crossings: [event('ma50x200', CrossDirection.up, 1500)]),
        ),
        isTrue,
      );
    });

    test('ignores the other direction', () {
      final a = goldenCross();

      expect(
        a.isMetBy(
          AlertInputs(
            crossings: [event('ma50x200', CrossDirection.down, 2000)],
          ),
        ),
        isFalse,
      );
    });

    test('ignores a different crossover', () {
      final a = goldenCross();

      expect(
        a.isMetBy(
          AlertInputs(crossings: [event('closex200', CrossDirection.up, 2000)]),
        ),
        isFalse,
      );
    });

    test('no crossings means no fire', () {
      expect(goldenCross().isMetBy(const AlertInputs(price: 999)), isFalse);
    });

    test('an alert naming a crossover this build dropped never fires', () {
      final a = alert(
        kind: AlertKind.crossover,
        crossoverId: 'no-such-crossover',
        direction: AlertDirection.above,
      );

      expect(a.crossover, isNull);
      expect(
        a.isMetBy(
          AlertInputs(
            crossings: [event('no-such-crossover', CrossDirection.up, 9000)],
          ),
        ),
        isFalse,
      );
      // Still readable in the list, so it can be found and deleted.
      expect(a.condition((v) => '$v'), 'Crossover no longer available');
    });
  });

  group('symbolsNeedingHistory', () {
    test('names only the symbols with an indicator alert', () {
      final alerts = [
        alert(id: 'p', symbol: 'AAPL', threshold: 200),
        alert(id: 'r', symbol: 'MSFT', kind: AlertKind.rsi, threshold: 30),
        alert(
          id: 'x',
          symbol: 'NVDA',
          kind: AlertKind.crossover,
          crossoverId: 'ma50x200',
        ),
      ];

      // A portfolio of plain price alerts must never pay for history.
      expect(symbolsNeedingHistory(alerts), {'MSFT', 'NVDA'});
      expect(symbolsToWatch(alerts), {'AAPL', 'MSFT', 'NVDA'});
    });

    test('skips disarmed alerts, like symbolsToWatch does', () {
      final alerts = [
        alert(id: 'off', kind: AlertKind.rsi, enabled: false),
        alert(id: 'done', kind: AlertKind.rsi, triggeredAt: 1),
      ];

      expect(symbolsNeedingHistory(alerts), isEmpty);
    });
  });

  group('alert storage compatibility', () {
    test('an alert stored before kinds existed loads as a price alert', () {
      final legacy = PriceAlert.fromJson({
        'id': 'a1',
        'symbol': 'AAPL',
        'direction': 'above',
        'threshold': 200.0,
        'currency': 'USD',
        'createdAt': 1,
        'enabled': true,
      });

      expect(legacy.kind, AlertKind.price);
      expect(legacy.crossoverId, isNull);
      expect(legacy.isMetBy(const AlertInputs(price: 250)), isTrue);
    });

    test('a crossover alert round-trips its kind and target', () {
      final original = alert(
        kind: AlertKind.crossover,
        crossoverId: 'closex200',
        direction: AlertDirection.below,
      );
      final restored = PriceAlert.fromJson(original.toJson());

      expect(restored.kind, AlertKind.crossover);
      expect(restored.crossoverId, 'closex200');
      expect(restored.direction, AlertDirection.below);
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
