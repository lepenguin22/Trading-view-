import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/api/yahoo.dart';
import 'package:ticker/background/alert_worker.dart';
import 'package:ticker/models/alert.dart';
import 'package:ticker/state/alert_storage.dart';
import 'package:ticker/state/alerts.dart';

import 'helpers.dart';

void main() {
  // The fixture quotes AAPL at 196.50.
  final chart1d = File('test/fixtures/chart-1d.json').readAsStringSync();

  YahooApi apiReturningFixture() => YahooApi(
    client: MockClient(
      (_) async => http.Response(
        chart1d,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('runAlertCheck', () {
    test('fires an alert the price satisfies and disarms it', () async {
      final storage = AlertStorage();
      await storage.save([testAlert(id: 'below-price', threshold: 150)]);

      final notifier = FakeNotifier();
      final fired = await runAlertCheck(
        api: apiReturningFixture(),
        storage: storage,
        notifier: notifier,
      );

      expect(fired.map((a) => a.id), ['below-price']);
      expect(notifier.fired.map((a) => a.id), ['below-price']);
      expect(notifier.prices.single, 196.5);

      // One-shot: the stored alert is switched off and stamped, so the next
      // pass does not notify again.
      final stored = await storage.load();
      expect(stored.single.enabled, isFalse);
      expect(stored.single.hasTriggered, isTrue);
    });

    test('leaves an unmet alert armed and untouched', () async {
      final storage = AlertStorage();
      await storage.save([testAlert(id: 'far-off', threshold: 500)]);

      final notifier = FakeNotifier();
      final fired = await runAlertCheck(
        api: apiReturningFixture(),
        storage: storage,
        notifier: notifier,
      );

      expect(fired, isEmpty);
      expect(notifier.fired, isEmpty);
      final stored = await storage.load();
      expect(stored.single.enabled, isTrue);
      expect(stored.single.hasTriggered, isFalse);
    });

    test('does nothing when no alerts are armed', () async {
      final notifier = FakeNotifier();
      final fired = await runAlertCheck(
        api: apiReturningFixture(),
        storage: AlertStorage(),
        notifier: notifier,
      );
      expect(fired, isEmpty);
      expect(notifier.fired, isEmpty);
    });

    test('does not fire when the feed fails', () async {
      // An unreachable feed must never be read as a threshold crossing.
      final storage = AlertStorage();
      await storage.save([testAlert(id: 'a', threshold: 1)]);

      final notifier = FakeNotifier();
      final fired = await runAlertCheck(
        api: YahooApi(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
        storage: storage,
        notifier: notifier,
      );

      expect(fired, isEmpty);
      expect(notifier.fired, isEmpty);
      expect((await storage.load()).single.enabled, isTrue);
    });

    test('preserves an alert added while the fetch was in flight', () async {
      // The worker re-reads storage before writing, so a concurrent edit from
      // the UI isolate is not clobbered.
      final storage = AlertStorage();
      await storage.save([testAlert(id: 'original', threshold: 150)]);

      final notifier = FakeNotifier();
      final api = YahooApi(
        client: MockClient((_) async {
          await storage.save([
            testAlert(id: 'original', threshold: 150),
            testAlert(id: 'added-meanwhile', symbol: 'MSFT', threshold: 999),
          ]);
          return http.Response(
            chart1d,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await runAlertCheck(api: api, storage: storage, notifier: notifier);

      final stored = await storage.load();
      expect(stored.map((a) => a.id), ['original', 'added-meanwhile']);
      expect(stored.firstWhere((a) => a.id == 'original').enabled, isFalse);
      expect(
        stored.firstWhere((a) => a.id == 'added-meanwhile').enabled,
        isTrue,
      );
    });
  });

  group('AlertsModel', () {
    /// Scheduling touches the platform, so record calls instead.
    Future<AlertsModel> modelWith(
      FakeNotifier notifier,
      List<List<PriceAlert>> scheduled,
    ) async {
      final model = AlertsModel(
        notifier: notifier,
        scheduler: (alerts) async => scheduled.add(alerts),
      );
      await model.start();
      return model;
    }

    test('adds an alert and schedules the background check', () async {
      final scheduled = <List<PriceAlert>>[];
      final model = await modelWith(FakeNotifier(), scheduled);

      final failure = await model.add(
        symbol: 'AAPL',
        direction: AlertDirection.above,
        threshold: 200,
        currency: 'USD',
      );

      expect(failure, isNull);
      expect(model.alerts, hasLength(1));
      expect(model.hasArmed('AAPL'), isTrue);
      expect(model.armedCount, 1);
      // Once on start, once after the add.
      expect(scheduled.last, hasLength(1));
    });

    test('rejects a non-positive threshold', () async {
      final model = await modelWith(FakeNotifier(), []);
      expect(
        await model.add(
          symbol: 'AAPL',
          direction: AlertDirection.above,
          threshold: 0,
          currency: 'USD',
        ),
        'Enter a price above zero.',
      );
      expect(model.alerts, isEmpty);
    });

    test('rejects an exact duplicate', () async {
      final model = await modelWith(FakeNotifier(), []);
      await model.add(
        symbol: 'AAPL',
        direction: AlertDirection.above,
        threshold: 200,
        currency: 'USD',
      );
      final second = await model.add(
        symbol: 'AAPL',
        direction: AlertDirection.above,
        threshold: 200,
        currency: 'USD',
      );
      expect(second, contains('already have that alert'));
      expect(model.alerts, hasLength(1));
    });

    test('cancels scheduling when the last alert is removed', () async {
      final scheduled = <List<PriceAlert>>[];
      final model = await modelWith(FakeNotifier(), scheduled);
      await model.add(
        symbol: 'AAPL',
        direction: AlertDirection.above,
        threshold: 200,
        currency: 'USD',
      );
      await model.remove(model.alerts.single.id);

      expect(model.alerts, isEmpty);
      expect(scheduled.last, isEmpty);
    });

    test('re-arming a fired alert clears its triggered state', () async {
      final model = await modelWith(FakeNotifier(), []);
      await model.add(
        symbol: 'AAPL',
        direction: AlertDirection.above,
        threshold: 200,
        currency: 'USD',
      );
      final id = model.alerts.single.id;

      await model.setEnabled(id, false);
      expect(model.armedCount, 0);

      await model.setEnabled(id, true);
      expect(model.alerts.single.hasTriggered, isFalse);
      expect(model.armedCount, 1);
    });
  });
}
