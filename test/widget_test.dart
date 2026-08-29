import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/api/yahoo.dart';
import 'package:ticker/main.dart';
import 'package:ticker/state/watchlist.dart';

/// A smoke test over the real widget tree: hydration from storage, the polling
/// timer, navigation and the watchlist rows all run for real, with only the
/// network faked. It catches the class of crash a static analysis cannot.

void main() {
  final chart1d = File('test/fixtures/chart-1d.json').readAsStringSync();

  late int requestCount;

  setUp(() {
    requestCount = 0;
    SharedPreferences.setMockInitialValues({});
  });

  /// Builds the app over a client that answers every request identically.
  Widget appWith(http.Client client) {
    return TickerApp(
      createModel: () => WatchlistModel(api: YahooApi(client: client)),
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
}
