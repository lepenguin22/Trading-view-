import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/api/yahoo.dart';
import 'package:ticker/main.dart';
import 'package:ticker/state/alerts.dart';
import 'package:ticker/widgets/price_chart.dart';

import 'helpers.dart';

/// A smoke test over the real widget tree: hydration from storage, the polling
/// timer, navigation and the watchlist rows all run for real, with only the
/// network faked. It catches the class of crash a static analysis cannot.

void main() {
  final chart1d = File('test/fixtures/chart-1d.json').readAsStringSync();

  late int requestCount;
  late FakeNotifier notifier;

  setUp(() {
    requestCount = 0;
    notifier = FakeNotifier();
    SharedPreferences.setMockInitialValues({});
  });

  /// Builds the app over a client that answers every request identically.
  ///
  /// Notifications and background scheduling are faked: both would otherwise
  /// reach for a platform that does not exist under `flutter test`.
  Widget appWith(http.Client client) {
    return TickerApp(
      createApi: () => YahooApi(client: client),
      createAlerts: () =>
          AlertsModel(notifier: notifier, scheduler: (_) async {}),
    );
  }

  MockClient respondingWith(String body, {int status = 200}) {
    return MockClient((_) async {
      requestCount++;
      return http.Response(
        body,
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  /// Tears the tree down so the model's polling timer is cancelled; a pending
  /// timer would otherwise fail the test.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('renders the default watchlist with live prices', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    // Every default symbol resolves to the same AAPL fixture, so one row is
    // enough to prove the pipeline ran end to end.
    expect(find.text('Apple Inc.'), findsWidgets);
    expect(find.textContaining('196.50'), findsWidgets);
    expect(find.text('+1.29%'), findsWidgets);

    await teardown(tester);
  });

  testWidgets('shows the per-symbol error message when the feed fails', (
    tester,
  ) async {
    final client = MockClient((_) async {
      requestCount++;
      throw http.ClientException('offline');
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach Yahoo Finance. Check your connection.'),
      findsWidgets,
    );

    await teardown(tester);
  });

  testWidgets('surfaces a rate limit rather than blanking the list', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith('{}', status: 429)));
    await tester.pumpAndSettle();

    expect(
      find.text('Rate limited by Yahoo Finance. Wait a moment and try again.'),
      findsWidgets,
    );

    await teardown(tester);
  });

  testWidgets('re-polls the feed on the refresh interval', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    final afterFirstLoad = requestCount;
    expect(afterFirstLoad, greaterThan(0));

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(requestCount, greaterThan(afterFirstLoad));

    await teardown(tester);
  });

  testWidgets('opens the detail screen for a tapped row', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('Remove from watchlist'), findsOneWidget);
    // The range picker only exists on the detail screen.
    expect(find.text('5Y'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('reaches the search screen from the add button', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Add symbol'), findsOneWidget);
    expect(find.text('Company name or ticker'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('creates a price alert from the detail screen', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // The alerts section sits below the chart and stats, so bring it on
    // screen before tapping.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Alert me when AAPL'), findsOneWidget);

    // The field is seeded with the current price; set an explicit threshold.
    await tester.enterText(find.byType(TextField), '250');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create alert'));
    await tester.pumpAndSettle();

    // Sheet closed, and the alert is listed against the symbol.
    expect(find.text('Alert me when AAPL'), findsNothing);
    expect(find.textContaining('rises to or above'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('warns when the alert condition is already met', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    // AAPL is at 196.50 in the fixture, so "above 100" already holds.
    await tester.enterText(find.byType(TextField), '100');
    await tester.pumpAndSettle();

    expect(find.textContaining('already meets this condition'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a new alert reaches the watchlist badge and alerts screen', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '250');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create alert'));
    await tester.pumpAndSettle();

    // Back to the watchlist: the app bar badge now shows one armed alert.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pumpAndSettle();
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.textContaining('rises to or above'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a foreground refresh fires a due alert', (tester) async {
    // Seed an alert AAPL already satisfies, then let the watchlist refresh.
    SharedPreferences.setMockInitialValues({
      'ticker.alerts.v1':
          '[{"id":"due","symbol":"AAPL","direction":"above","threshold":10,'
          '"currency":"USD","createdAt":1,"enabled":true}]',
    });

    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    expect(notifier.fired.map((a) => a.id), ['due']);
    expect(notifier.prices.single, 196.5);

    await teardown(tester);
  });

  testWidgets('shows candlesticks by default and toggles to a line', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // The toggle offers the *other* style, so "Line" showing means candles
    // are what is currently drawn.
    expect(find.widgetWithText(TextButton, 'Line'), findsOneWidget);
    expect(find.byType(PriceChart), findsOneWidget);
    expect(
      tester.widget<PriceChart>(find.byType(PriceChart)).style,
      ChartStyle.candles,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Line'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<PriceChart>(find.byType(PriceChart)).style,
      ChartStyle.line,
    );
    expect(find.widgetWithText(TextButton, 'Candles'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('scrubbing the chart reveals the bar OHLC', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // Nothing scrubbed yet, so the header shows the range caption instead.
    expect(find.text('O '), findsNothing);

    final chart = find.byType(PriceChart);
    final centre = tester.getCenter(chart);
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pumpAndSettle();

    // The O/H/L/C strip replaces the caption while a finger is down.
    expect(find.text('O '), findsOneWidget);
    expect(find.text('H '), findsOneWidget);
    expect(find.text('L '), findsOneWidget);
    expect(find.text('C '), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('O '), findsNothing);

    await teardown(tester);
  });
}
