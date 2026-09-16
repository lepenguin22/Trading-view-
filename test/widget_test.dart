import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/api/yahoo.dart';
import 'package:ticker/main.dart';
import 'package:ticker/api/portfolio_source.dart';
import 'package:ticker/screens/import_screen.dart';
import 'package:ticker/screens/settings_screen.dart';
import 'package:ticker/screens/watchlist_screen.dart';
import 'package:ticker/state/alerts.dart';
import 'package:ticker/state/storage.dart';
import 'package:ticker/state/watchlist.dart';
import 'package:ticker/theme/app_theme.dart';
import 'package:ticker/models/crossover.dart';
import 'package:ticker/models/holding.dart';
import 'package:ticker/utils/format.dart';
import 'package:ticker/models/types.dart';
import 'package:ticker/widgets/portfolio_summary.dart';
import 'package:ticker/widgets/price_chart.dart';
import 'package:ticker/widgets/rsi_pane.dart';

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

  /// Captures the URLs the app asks the platform to open.
  ///
  /// `url_launcher` has no Dart-side fake, and left unmocked its future never
  /// completes under test, so the tap appears to do nothing.
  List<String> mockLauncher(WidgetTester tester) {
    final launched = <String>[];
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, (
      call,
    ) async {
      final url = (call.arguments as Map)['url'];
      if (url is String) launched.add(url);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockMethodCallHandler(launcher, null);
    });
    return launched;
  }

  /// Taps the detail screen's analysis button.
  Future<void> tapAnalysis(WidgetTester tester) async {
    final button = find.widgetWithText(
      OutlinedButton,
      'Run framework analysis',
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Whether [text] appears inside the list row for [symbol].
  ///
  /// Scoped to the row on purpose. The portfolio total above the list carries
  /// the same kind of figure, so a bare `find.text` would pass on the wrong
  /// widget and stop proving that the row itself says anything.
  bool rowFigure(WidgetTester tester, String symbol, String text) {
    final row = find.ancestor(
      of: find.text(symbol),
      matching: find.byType(InkWell),
    );
    expect(row, findsWidgets, reason: 'no list row found for $symbol');
    return tester
        .widgetList<Text>(
          find.descendant(of: row.first, matching: find.byType(Text)),
        )
        .any((t) => t.data == text);
  }

  /// Whether [text] appears inside the portfolio summary above the list.
  ///
  /// The counterpart to [rowFigure]: a one-holding portfolio's total equals
  /// that holding's row value, so neither assertion proves anything unless it
  /// says which of the two it means.
  bool summaryFigure(WidgetTester tester, String text) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PortfolioSummary),
          matching: find.byType(Text),
        ),
      )
      .any((t) => t.data == text);

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

  testWidgets('the open detail screen is polled faster than the list', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    final afterOpen = requestCount;

    // Well short of the 60s list interval, so anything fetched here is the
    // focused symbol being polled on its own, faster clock.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    final duringFocus = requestCount - afterOpen;
    expect(duringFocus, greaterThan(0));
    // One symbol per poll, not the whole list: at ~10s that is a handful of
    // requests in 30s, nowhere near a request per holding.
    expect(duringFocus, lessThan(6));

    await teardown(tester);
  });

  testWidgets('closing the detail screen stops the fast polling', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    final afterClose = requestCount;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(requestCount, afterClose);

    await teardown(tester);
  });

  testWidgets('opens the detail screen for a tapped row', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('Remove from watchlist'), findsOneWidget);
    // The zoom controls only exist on the detail screen.
    expect(find.byTooltip('Zoom in, fewer days'), findsOneWidget);

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

  testWidgets('the analysis button copies the prompt even if Claude will not '
      'open', (tester) async {
    // url_launcher has no platform behind it under flutter test, so launching
    // fails — which is exactly the path that must still leave the user able to
    // run the analysis.
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    // Answers "could not open" deterministically, rather than leaving the
    // plugin with no platform behind it and the future never completing.
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      launcher,
      (call) async => false,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockMethodCallHandler(launcher, null);
    });

    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    await tapAnalysis(tester);

    // The prompt is on the clipboard before the project question is answered,
    // so it is there however that goes.
    expect(clipboard, ['Run the framework on AAPL']);

    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();

    expect(clipboard, ['Run the framework on AAPL']);
    // And the user is told what to do with it rather than left guessing.
    expect(find.textContaining('Paste it into Claude'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('the analysis button opens Claude carrying the prompt', (
    tester,
  ) async {
    final launched = mockLauncher(tester);

    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tapAnalysis(tester);

    // No project is configured, so the app says where this is about to go
    // rather than opening a bare chat behind the user's back.
    expect(find.text('No Claude project set'), findsOneWidget);
    expect(launched, isEmpty);

    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();

    expect(launched, hasLength(1));
    final uri = Uri.parse(launched.single);
    expect(uri.host, 'claude.ai');
    expect(uri.path, '/new');
    // The prompt survives being put in the link, rather than the link merely
    // opening a blank chat.
    expect(uri.queryParameters['q'], 'Run the framework on AAPL');
    expect(find.textContaining('Opening Claude'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('declining the bare chat opens nothing', (tester) async {
    final launched = mockLauncher(tester);

    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tapAnalysis(tester);

    // "Set project" goes to settings instead of opening the wrong chat.
    await tester.tap(find.text('Set project'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('the analysis button opens the saved project', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.analysis.claudeProject.v1': 'https://claude.ai/project/abc123',
    });

    final launched = mockLauncher(tester);

    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tapAnalysis(tester);

    // A configured project goes straight there — no question to answer.
    expect(find.text('No Claude project set'), findsNothing);

    expect(launched, hasLength(1));
    final uri = Uri.parse(launched.single);
    expect(uri.path, '/project/abc123');

    // No `?q=`: that is the new-chat route's parameter, and carrying it on a
    // project link risks landing in a bare chat, which is the whole point of
    // having a project link. The clipboard carries the prompt.
    expect(uri.query, isEmpty);
    expect(find.textContaining('Opening your project'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('creates an RSI alert from the sheet', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RSI'));
    await tester.pumpAndSettle();

    // Switching kind reseeds the level: a price would be a nonsensical RSI.
    expect(find.text('RSI level'), findsOneWidget);
    await tester.tap(find.text('Below'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '30',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create alert'));
    await tester.pumpAndSettle();

    expect(find.text('Alert me when AAPL'), findsNothing);
    expect(find.textContaining('RSI below 30'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('creates a Golden Cross alert from the sheet', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crossover'));
    await tester.pumpAndSettle();

    // Concrete named conditions, not a spec plus a direction to combine.
    expect(find.text('Golden Cross'), findsOneWidget);
    expect(find.text('Death Cross'), findsOneWidget);
    // No level to enter, so no numeric field at all.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Death Cross'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create alert'));
    await tester.pumpAndSettle();

    expect(find.text('Alert me when AAPL'), findsNothing);
    expect(find.textContaining('Death Cross'), findsWidgets);

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

  testWidgets('long pressing the chart reveals the bar OHLC', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // Nothing scrubbed yet, so the header shows the window caption instead.
    expect(find.text('O '), findsNothing);

    // A plain drag now pans, so the crosshair is behind a long press.
    final centre = tester.getCenter(find.byType(PriceChart));
    final gesture = await tester.startGesture(centre);
    // Past the long-press threshold, so the crosshair takes the gesture
    // rather than the pan.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(12, 0));
    await tester.pumpAndSettle();

    expect(find.text('O '), findsOneWidget);
    expect(find.text('H '), findsOneWidget);
    expect(find.text('L '), findsOneWidget);
    expect(find.text('C '), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('O '), findsNothing);

    await teardown(tester);
  });

  /// A chart payload with [count] bars, so the longer indicators can warm up.
  /// The fixture only carries four.
  String syntheticChart(int count) {
    final t = <int>[];
    final o = <String>[];
    final h = <String>[];
    final l = <String>[];
    final c = <String>[];
    for (var i = 0; i < count; i++) {
      final base = 100 + (i % 11) - 5 + i * 0.1;
      t.add(1700000000 + i * 300);
      o.add(base.toStringAsFixed(4));
      h.add((base + 1).toStringAsFixed(4));
      l.add((base - 1).toStringAsFixed(4));
      c.add((base + 0.5).toStringAsFixed(4));
    }
    return '{"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL",'
        '"regularMarketPrice":100,"previousClose":99,"longName":"Apple Inc.",'
        '"marketState":"REGULAR"},"timestamp":[${t.join(",")}],'
        '"indicators":{"quote":[{"open":[${o.join(",")}],'
        '"high":[${h.join(",")}],"low":[${l.join(",")}],'
        '"close":[${c.join(",")}]}]}}],"error":null}}';
  }

  testWidgets('shows moving averages and RSI once enough bars exist', (
    tester,
  ) async {
    // Long enough for the 200-day average to cover the whole default window.
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // The legend is always present, so three same-shaped lines are never
    // identified by colour alone.
    for (final label in ['MA20', 'MA50', 'MA200']) {
      expect(find.text(label), findsOneWidget);
    }
    // With 150 bars every period has warmed up, so none read n/a.
    expect(find.text('n/a'), findsNothing);

    expect(find.text('RSI (14)'), findsOneWidget);
    // The RSI readout is a number, not the em dash placeholder.
    final rsiRow = find.ancestor(
      of: find.text('RSI (14)'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: rsiRow.first, matching: find.text('—')),
      findsNothing,
    );

    await teardown(tester);
  });

  testWidgets('marks a moving average unavailable on too short a range', (
    tester,
  ) async {
    // The fixture has four bars, so no period can warm up.
    await tester.pumpWidget(appWith(respondingWith(chart1d)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // Shown but flagged, rather than silently absent. Asserted per chip
    // rather than by counting every n/a on the screen, so adding a legend
    // entry elsewhere does not silently change what this test checks.
    for (final label in ['MA20', 'MA50', 'MA200']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.first, matching: find.text('n/a')),
        findsOneWidget,
        reason: '$label should read n/a on a four-bar range',
      );
    }

    await teardown(tester);
  });

  testWidgets('tapping a legend chip toggles that average off', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    PriceChart chartWidget() =>
        tester.widget<PriceChart>(find.byType(PriceChart));
    expect(chartWidget().overlays, hasLength(3));

    await tester.tap(find.text('MA50'));
    await tester.pumpAndSettle();

    final periods = chartWidget().overlays.map((o) => o.period);
    expect(periods, [20, 200]);

    await tester.tap(find.text('MA50'));
    await tester.pumpAndSettle();
    expect(chartWidget().overlays, hasLength(3));

    await teardown(tester);
  });

  testWidgets('opens on the most recent bars, not the whole series', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    final chart = tester.widget<PriceChart>(find.byType(PriceChart));
    // 90 days by default, anchored to the newest bar.
    expect(chart.window.count, 90);
    expect(chart.window.end, 400);
    expect(find.text('90 days'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('the zoom buttons change how many days are shown', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    int visible() =>
        tester.widget<PriceChart>(find.byType(PriceChart)).window.count;
    expect(visible(), 90);

    await tester.tap(find.byTooltip('Zoom in, fewer days'));
    await tester.pumpAndSettle();
    expect(visible(), lessThan(90));

    final zoomedIn = visible();
    await tester.tap(find.byTooltip('Zoom out, more days'));
    await tester.pumpAndSettle();
    expect(visible(), greaterThan(zoomedIn));

    await teardown(tester);
  });

  testWidgets('dragging pans through history without changing the zoom', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    ChartWindow window() =>
        tester.widget<PriceChart>(find.byType(PriceChart)).window;
    final before = window();

    // Dragging right pulls older bars into view.
    await tester.drag(find.byType(PriceChart), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(window().start, lessThan(before.start));
    expect(window().count, before.count, reason: 'panning must not zoom');

    await teardown(tester);
  });

  testWidgets('cannot pan past the start of the series', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(150))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(PriceChart), const Offset(300, 0));
      await tester.pumpAndSettle();
    }

    final window = tester.widget<PriceChart>(find.byType(PriceChart)).window;
    expect(window.start, 0);
    expect(window.count, 90);

    await teardown(tester);
  });

  testWidgets('draws a price axis whose labels track the visible bars', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // The axis is painted, not composed of widgets, so assert on the values
    // it is handed rather than on rendered text.
    final chart = tester.widget<PriceChart>(find.byType(PriceChart));
    final visible = chart.candles.sublist(chart.window.start, chart.window.end);
    var low = visible.first.low;
    var high = visible.first.high;
    for (final candle in visible) {
      if (candle.low < low) low = candle.low;
      if (candle.high > high) high = candle.high;
    }

    final ticks = priceTicksFor(low, high, chart.currency);
    expect(ticks, isNotEmpty);
    for (final tick in ticks) {
      expect(tick.price, inInclusiveRange(low, high));
      expect(tick.label, isNotEmpty);
    }
    // Something must be reserved for the labels, or the plot would draw over
    // them.
    expect(priceAxisWidth([for (final t in ticks) t.label]), greaterThan(0));

    await teardown(tester);
  });

  testWidgets('the axis rescales when the window zooms', (tester) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    List<PriceTick> ticksNow() {
      final chart = tester.widget<PriceChart>(find.byType(PriceChart));
      final visible = chart.candles.sublist(
        chart.window.start,
        chart.window.end,
      );
      var low = visible.first.low;
      var high = visible.first.high;
      for (final candle in visible) {
        if (candle.low < low) low = candle.low;
        if (candle.high > high) high = candle.high;
      }
      return priceTicksFor(low, high, chart.currency);
    }

    final before = ticksNow();

    // Zooming in narrows the price range, so the axis must follow it rather
    // than staying pinned to the whole series.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Zoom in, fewer days'));
      await tester.pumpAndSettle();
    }

    final after = ticksNow();
    expect(after, isNotEmpty);
    final beforeSpan = before.last.price - before.first.price;
    final afterSpan = after.last.price - after.first.price;
    expect(afterSpan, lessThanOrEqualTo(beforeSpan));

    await teardown(tester);
  });

  testWidgets('the RSI pane reserves the same gutter as the price axis', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(respondingWith(syntheticChart(400))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    final rsi = tester.widget<RsiPane>(find.byType(RsiPane));
    // Non-zero and finite: the two plots share an x-axis only if the pane
    // sets aside the same width the chart's labels occupy.
    expect(rsi.gutter, greaterThan(0));
    expect(rsi.gutter.isFinite, isTrue);

    final chart = tester.widget<PriceChart>(find.byType(PriceChart));
    expect(rsi.window, chart.window);

    await teardown(tester);
  });

  /// A chart payload naming [symbol], so a fake feed can resolve any ticker
  /// an import asks for while still rejecting the ones a test wants to fail.
  String quoteFor(String symbol) =>
      '{"chart":{"result":[{"meta":{"currency":"USD","symbol":"$symbol",'
      '"regularMarketPrice":100,"previousClose":99,"longName":"$symbol Inc",'
      '"marketState":"REGULAR"},"timestamp":[1700000000],'
      '"indicators":{"quote":[{"open":[99],"high":[101],"low":[98],'
      '"close":[100]}]}}],"error":null}}';

  /// Answers quote requests by echoing the symbol, except those in [reject].
  MockClient feedResolving({Set<String> reject = const {}}) {
    return MockClient((request) async {
      requestCount++;
      final path = Uri.decodeComponent(request.url.path);
      final symbol = path.split('/').last;
      if (reject.contains(symbol)) {
        return http.Response(
          '',
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        quoteFor(symbol),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  PortfolioSource sheetReturning(String body) => PortfolioSource(
    client: MockClient(
      (_) async =>
          http.Response(body, 200, headers: {'content-type': 'text/csv'}),
    ),
  );

  const holdingsCsv = 'Ticker,Shares\nAAPL,10\nMSFT,5\nNVDA,2\n';

  testWidgets('an import fills the portfolio and leaves the watchlist alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    final model = Provider.of<WatchlistModel>(
      tester.element(find.byType(WatchlistScreen)),
      listen: false,
    );

    final outcome = await model.importPortfolio([
      Holding(symbol: 'MSFT'),
      Holding(symbol: 'NVDA'),
    ]);
    await tester.pumpAndSettle();

    expect(outcome.added, ['MSFT', 'NVDA']);
    expect(model.portfolioSymbols, ['MSFT', 'NVDA']);
    // The watchlist is a separate list and an import must not touch it.
    expect(model.symbols, ['AAPL']);

    await teardown(tester);
  });

  testWidgets('re-importing mirrors the sheet, removing what it dropped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.symbols.v1': '["AAPL","MSFT","NVDA"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    final model = Provider.of<WatchlistModel>(
      tester.element(find.byType(WatchlistScreen)),
      listen: false,
    );
    expect(model.portfolioSymbols, ['AAPL', 'MSFT', 'NVDA']);

    // The sheet no longer lists NVDA, and now lists TSLA.
    final outcome = await model.importPortfolio([
      Holding(symbol: 'AAPL'),
      Holding(symbol: 'MSFT'),
      Holding(symbol: 'TSLA'),
    ]);
    await tester.pumpAndSettle();

    expect(outcome.added, ['TSLA']);
    expect(outcome.removed, ['NVDA'], reason: 'sold holdings must drop out');
    expect(outcome.unchanged, ['AAPL', 'MSFT']);
    expect(model.portfolioSymbols, ['AAPL', 'MSFT', 'TSLA']);

    await teardown(tester);
  });

  testWidgets('a symbol the feed rejects is kept, not dropped', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(appWith(feedResolving(reject: {'NVDA'})));
    await tester.pumpAndSettle();

    final model = Provider.of<WatchlistModel>(
      tester.element(find.byType(WatchlistScreen)),
      listen: false,
    );

    final outcome = await model.importPortfolio([
      Holding(symbol: 'MSFT'),
      Holding(symbol: 'NVDA'),
    ]);
    await tester.pumpAndSettle();

    // The sheet is the authority on what is held; a failed request must not
    // delete a holding.
    expect(model.portfolioSymbols, ['MSFT', 'NVDA']);
    expect(outcome.failed.keys, ['NVDA']);

    await teardown(tester);
  });

  testWidgets('both lists are polled together', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.symbols.v1': '["MSFT"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    final model = Provider.of<WatchlistModel>(
      tester.element(find.byType(WatchlistScreen)),
      listen: false,
    );

    // One quote map covers both lists, so a row on either has a price.
    expect(model.quotes.keys, containsAll(['AAPL', 'MSFT']));

    await teardown(tester);
  });

  testWidgets('the tabs show both lists and their counts', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.symbols.v1': '["MSFT","NVDA"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    expect(find.text('Watchlist (1)'), findsOneWidget);
    expect(find.text('Portfolio (2)'), findsOneWidget);

    // The watchlist tab is showing, so its symbol is on screen and the
    // portfolio's are not.
    expect(find.text('AAPL'), findsOneWidget);

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('NVDA'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('the portfolio shows a total and per-row values', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10},{"symbol":"MSFT","shares":5}]',
    });

    // Every symbol resolves at 100, so 15 shares are worth 1,500.
    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    expect(find.byType(PortfolioSummary), findsOneWidget);
    expect(find.text('\$1,500.00'), findsOneWidget);
    expect(find.text('2 holdings'), findsOneWidget);

    // And each row states its own size and worth, in its own row rather than
    // anywhere on the screen: the totals above carry the same kind of figure.
    expect(rowFigure(tester, 'AAPL', '10 shares'), isTrue);
    expect(rowFigure(tester, 'AAPL', '\$1,000.00'), isTrue);
    expect(rowFigure(tester, 'MSFT', '5 shares'), isTrue);
    expect(rowFigure(tester, 'MSFT', '\$500.00'), isTrue);

    await teardown(tester);
  });

  testWidgets('the portfolio shows gain per row and in the total', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"costPerShare":80},'
          '{"symbol":"MSFT","shares":5,"costPerShare":125}]',
    });

    // Everything resolves at 100: AAPL cost 800 now 1000, MSFT cost 625 now
    // 500. Together 1425 paid, 1500 now, so +75.
    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Since bought'), findsOneWidget);
    expect(find.textContaining('+\$75.00'), findsOneWidget);

    // Per row, as a percentage: +25.00% and −20.00%.
    expect(find.text('+25.00%'), findsOneWidget);
    expect(find.text('−20.00%'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a gain over fewer holdings than the value says so', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"costPerShare":80},'
          '{"symbol":"MSFT","shares":5}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    // Both are valued, so the total covers 2 holdings...
    expect(find.text('2 holdings'), findsOneWidget);
    expect(find.text('\$1,500.00'), findsOneWidget);
    // ...but only one has a cost, and the gain must not read as the whole
    // portfolio's return.
    expect(find.text('of 1'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a portfolio with no costs shows no gain line', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1': '[{"symbol":"AAPL","shares":10}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    // The value still shows; there is simply no return to report.
    expect(summaryFigure(tester, '\$1,000.00'), isTrue);
    expect(find.text('Since bought'), findsNothing);

    await teardown(tester);
  });

  testWidgets('the calculator can start from the imported portfolio', (
    tester,
  ) async {
    // Holdings priced at 100 apiece by the fake feed, so 15 shares are worth
    // 1,500 — in USD, while the calculator projects in SGD alongside CPF.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10},{"symbol":"MSFT","shares":5}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculator'));
    await tester.pumpAndSettle();

    expect(find.text(r'$1,500.00 USD'), findsOneWidget);

    // A USD balance cannot join an SGD projection without a rate, and both
    // print a bare "$" — so the button stays disabled until one is given.
    final button = find.widgetWithText(
      OutlinedButton,
      'Use as "Invested today"',
    );
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'USD to SGD'),
      '1.28',
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$1,920.00'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    // Taken into the field, converted, where it stays until taken again.
    // The first "Invested today" on the screen: the extra investment pots
    // below carry the same label, and the import only ever feeds this one.
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Invested today').first,
          )
          .controller!
          .text,
      '1920.00',
    );

    await teardown(tester);
  });

  testWidgets('a holding shows the scale its scores were marked on', (
    tester,
  ) async {
    // The framework drops criteria that do not apply, so a real sheet holds
    // 12/17 beside 15/18. Printing a fixed /19 would misstate both.
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"UNH","shares":16,'
          '"financialScore":{"value":12,"outOf":17},'
          '"moatScore":{"value":8,"outOf":14}},'
          '{"symbol":"PLTR","shares":19,'
          '"financialScore":{"value":15,"outOf":18},'
          '"moatScore":{"value":6,"outOf":14}}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Fin 12/17 · Moat 8/14'), findsOneWidget);
    expect(find.text('Fin 15/18 · Moat 6/14'), findsOneWidget);
    expect(find.textContaining('/19'), findsNothing);

    await teardown(tester);
  });

  testWidgets('a holding shows its checklist scores and their age', (
    tester,
  ) async {
    final scoredAt = DateTime.now().subtract(const Duration(days: 21));
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14,'
          '"moatScore":11,"scoredAt":${scoredAt.millisecondsSinceEpoch}}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Fin 14/19 · Moat 11/14'), findsOneWidget);
    expect(find.text('scored 3 weeks ago'), findsOneWidget);
    // The age and the date both, the date on its own line — the age says
    // whether earnings have overtaken the score, the date says whether it is
    // the one in the sheet, and neither answers for the other.
    expect(find.text(formatScoredOn(scoredAt)), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('an undated score leaves no empty line where a date would be', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14,'
          '"noDateReason":"noColumn"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    // Only the message. A blank second line would be a gap with no cause.
    expect(find.text('no date column'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{4}$')), findsNothing);

    await teardown(tester);
  });

  testWidgets('the date gets a whole line, so a narrow phone cannot cut it', (
    tester,
  ) async {
    // The reason the date is on its own line at all. Beside the age, sharing
    // what is left of 360 logical pixels after "Fin 14/19 · Moat 11/14", the
    // date is the half that gets cut — and it is the half that cannot be
    // worked out from the other.
    //
    // Only the date is checked. Widget tests render in Ahem, where every
    // glyph is a full em square, so "scored 9 months ago · stale" measures
    // 317 logical pixels here against roughly 155 in a real font. Any
    // assertion about that line would be measuring the test font. The date
    // line has the full row to itself, which is wide enough to hold even the
    // Ahem rendering — so what it proves holds outside the test too.
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scoredAt = DateTime.now().subtract(const Duration(days: 260));
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"costPerShare":123.45,'
          '"financialScore":14,"moatScore":11,'
          '"scoredAt":${scoredAt.millisecondsSinceEpoch}}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Rendered in full, not merely present: find.text matches a widget's data
    // even when the paragraph ellipsized it on screen, so the check that
    // means anything here is whether the line overran its one allowed line.
    final date = find.text(formatScoredOn(scoredAt));
    expect(find.textContaining('stale'), findsOneWidget);
    expect(date, findsOneWidget);

    // Rendered in full, not merely present: find.text matches a widget's data
    // even when the paragraph ellipsized it on screen, so the check that
    // means anything is whether the line overran its one allowed line.
    final rendered = tester.renderObject<RenderParagraph>(date);
    expect(rendered.didExceedMaxLines, isFalse, reason: 'the date was cut off');
    expect(
      rendered.getMaxIntrinsicWidth(double.infinity),
      lessThan(rendered.size.width),
      reason: 'the date line has room to spare',
    );

    await teardown(tester);
  });

  testWidgets('a stale score is called stale, not coloured like a loss', (
    tester,
  ) async {
    final scoredAt = DateTime.now().subtract(const Duration(days: 260));
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":8,'
          '"moatScore":4,"scoredAt":${scoredAt.millisecondsSinceEpoch}}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    // Said in words. Red is already the loss colour on this row, so staleness
    // must not be carried by colour alone.
    final label = find.textContaining('stale');
    expect(label, findsOneWidget);

    final colors = Theme.of(tester.element(label)).extension<AppColors>()!;
    expect(tester.widget<Text>(label).style?.color, isNot(colors.down));

    await teardown(tester);
  });

  testWidgets('a score with no readable date says so', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    // Only one score, and no date — the score still shows, but it must not
    // look timeless. A save from before the reason was recorded cannot say
    // which of the three kinds of missing this was, so it says the least.
    expect(find.text('Fin 14/19'), findsOneWidget);
    expect(find.text('no date'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a sheet with no date column says that, not "no date"', (
    tester,
  ) async {
    // The two were one message once, and they send the reader to different
    // places: a missing column is the sheet's layout — most often a published
    // CSV frozen before the column was added — not a cell to reformat.
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14,'
          '"noDateReason":"noColumn"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(find.text('no date column'), findsOneWidget);
    expect(find.text('no date'), findsNothing);

    await teardown(tester);
  });

  testWidgets('a cell that could not be read says the date is unreadable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14,'
          '"noDateReason":"unreadable"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(find.text('date unreadable'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a reason this build does not know reads as no reason', (
    tester,
  ) async {
    // Forward compatibility: a name written by a later build must not crash
    // the list or print itself raw. An unknown reason is no reason, which is
    // what the oldest saves already mean.
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"financialScore":14,'
          '"noDateReason":"somethingNewer"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(find.text('no date'), findsOneWidget);
    expect(find.textContaining('somethingNewer'), findsNothing);

    await teardown(tester);
  });

  testWidgets('a holding with no scores shows no score line', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1': '[{"symbol":"AAPL","shares":10}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fin '), findsNothing);
    expect(find.text('no date'), findsNothing);

    await teardown(tester);
  });

  testWidgets('the watchlist never shows scores, only the portfolio does', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"MSFT","shares":10,"financialScore":14}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    // The watchlist tab is showing.
    expect(find.textContaining('Fin '), findsNothing);

    await teardown(tester);
  });

  testWidgets('the watchlist has no total, since it holds nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.holdings.v1': '[{"symbol":"MSFT","shares":5}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    expect(find.byType(PortfolioSummary), findsNothing);
    expect(find.textContaining('shares'), findsNothing);

    await teardown(tester);
  });

  testWidgets('a holding with no share count says so in the total', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10},{"symbol":"MSFT"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    expect(summaryFigure(tester, '\$1,000.00'), isTrue);
    expect(find.text('1 holding'), findsOneWidget);
    // Named rather than quietly left out of the sum.
    expect(find.textContaining('1 holding not counted'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a portfolio with no quantities shows no total at all', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.symbols.v1': '["AAPL","MSFT"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portfolio (2)'));
    await tester.pumpAndSettle();

    // A zero would claim the portfolio is worth nothing. The summary is built
    // but renders nothing, so assert on what it draws rather than on whether
    // the widget exists. The rows themselves are still listed.
    expect(
      find.descendant(
        of: find.byType(PortfolioSummary),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(find.text('AAPL'), findsOneWidget);

    await teardown(tester);
  });

  /// Pumps the import screen over a model built for the test.
  ///
  /// The model is created directly rather than lifted out of a TickerApp tree:
  /// swapping trees disposes the old model, and a disposed model refuses the
  /// import.
  Future<WatchlistModel> pumpImportScreen(
    WidgetTester tester, {
    required http.Client feed,
    required PortfolioSource source,
  }) async {
    final model = WatchlistModel(api: YahooApi(client: feed));
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: ChangeNotifierProvider<WatchlistModel>.value(
          value: model,
          child: ImportScreen(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('the import screen reports what a sheet fetch produced', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final model = await pumpImportScreen(
      tester,
      feed: feedResolving(),
      source: sheetReturning(holdingsCsv),
    );

    await tester.enterText(
      find.byType(TextField),
      'https://docs.google.com/spreadsheets/d/e/x/pub?output=csv',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio updated'), findsOneWidget);
    expect(find.textContaining('Added (3)'), findsOneWidget);
    expect(model.portfolioSymbols, ['AAPL', 'MSFT', 'NVDA']);
    expect(model.symbols, isEmpty, reason: 'the watchlist is untouched');

    model.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a failing ticker is named rather than silently dropped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final model = await pumpImportScreen(
      tester,
      feed: feedResolving(reject: {'NVDA'}),
      source: sheetReturning(holdingsCsv),
    );

    await tester.enterText(find.byType(TextField), 'https://example.com/x.csv');
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Kept, but no price'), findsOneWidget);
    // Named, so the user knows which cell in the sheet to fix.
    expect(find.textContaining('NVDA —'), findsOneWidget);
    // Kept: the sheet says it is held, so a failed request must not drop it.
    expect(model.portfolioSymbols, ['AAPL', 'MSFT', 'NVDA']);

    model.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the import screen surfaces an unpublished sheet clearly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final model = await pumpImportScreen(
      tester,
      feed: feedResolving(),
      source: sheetReturning('<!doctype html><html>Sign in</html>'),
    );

    await tester.enterText(find.byType(TextField), 'https://example.com/x.csv');
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Publish to web'), findsWidgets);
    // A failed fetch must never empty the portfolio.
    expect(model.portfolioSymbols, isEmpty);

    model.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the app bar fits a narrow phone', (tester) async {
    // The default test surface is 800px wide, which hides overflow. A real
    // phone is around 360dp, and the title now sits beside two action icons.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.symbols.v1': '["MSFT"]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    // A RenderFlex overflow fails the test, so reaching here is the assertion.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Watchlist (1)'), findsOneWidget);

    await teardown(tester);
  });

  /// A chart payload of [closes] as daily bars, so a test can hand the detail
  /// screen a series long enough for a 200-bar average to exist at all.
  String seriesChart(List<double> closes) {
    const day = 86400;
    const start = 1600000000;
    final times = [for (var i = 0; i < closes.length; i++) start + i * day]
        .join(',');
    final values = closes.map((c) => c.toStringAsFixed(2)).join(',');
    return '{"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL",'
        '"regularMarketPrice":${closes.last},"previousClose":${closes.first},'
        '"longName":"Apple Inc","marketState":"REGULAR"},'
        '"timestamp":[$times],"indicators":{"quote":[{"open":[$values],'
        '"high":[$values],"low":[$values],"close":[$values]}]}}],'
        '"error":null}}';
  }

  /// Falls then rises, so both moving averages and the price genuinely cross
  /// the 200 line rather than starting on one side of it.
  final valley = <double>[
    for (var i = 0; i < 200; i++) 300 - i.toDouble(),
    for (var i = 0; i < 200; i++) 100 + i.toDouble(),
  ];

  Future<void> openDetail(WidgetTester tester, List<double> closes) async {
    await tester.pumpWidget(appWith(respondingWith(seriesChart(closes))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();
  }

  testWidgets('a big holding lays out on a narrow phone', (tester) async {
    // 360 logical pixels wide, and figures large enough to be awkward: a
    // six-figure position, a four-figure share count and both scores. A
    // RenderFlex overflow anywhere in here fails the test on its own.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"D05.SI","shares":2400,"costPerShare":51.2,'
          '"financialScore":14,"moatScore":11,"scoredAt":"2026-03-12"}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();

    // Quoted at 100 against a cost of 51.20: 2,400 shares worth 240,000, and
    // a day change of +1 a share on the summary above.
    expect(rowFigure(tester, 'D05.SI', '2,400 shares'), isTrue);
    expect(rowFigure(tester, 'D05.SI', '\$240,000.00'), isTrue);
    expect(rowFigure(tester, 'D05.SI', '+95.31%'), isTrue);
    expect(summaryFigure(tester, '\$240,000.00'), isTrue);

    // Each figure gets its own column, so they line up down the list rather
    // than running together as one string.
    expect(find.textContaining('shares · '), findsNothing);

    await teardown(tester);
  });

  testWidgets('the detail screen states what the position is worth', (
    tester,
  ) async {
    // 10 shares bought at 80, quoted at 100 with a previous close of 99.
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1':
          '[{"symbol":"AAPL","shares":10,"costPerShare":80}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('Your position'), findsOneWidget);
    expect(find.text('Average cost'), findsOneWidget);
    expect(find.text('\$80.00'), findsOneWidget);
    expect(find.text('\$800.00'), findsOneWidget);
    expect(find.text('\$1,000.00'), findsOneWidget);

    // The day's move on the position, not on one share: the price moved 1,
    // and ten shares are held.
    expect(find.text('+\$10.00'), findsOneWidget);
    expect(find.text('+\$200.00'), findsOneWidget);
    expect(find.text('+25.00%'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a position with no cost shows no return it cannot compute', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
      'ticker.portfolio.holdings.v1': '[{"symbol":"AAPL","shares":10}]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    // Worth and today's move need only a quantity, so they stay.
    expect(find.text('Position value'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    // The rest need a purchase price the sheet never gave.
    expect(find.text('Average cost'), findsNothing);
    expect(find.text('Cost basis'), findsNothing);
    expect(find.text('Total return'), findsNothing);

    await teardown(tester);
  });

  testWidgets('a watchlist symbol gets no position section', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
      'ticker.portfolio.holdings.v1': '[]',
    });

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('Your position'), findsNothing);

    await teardown(tester);
  });

  testWidgets('the chart legend offers each crossover', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
    });

    await openDetail(tester, valley);

    for (final spec in crossoverSpecs) {
      expect(
        find.text(spec.label),
        findsOneWidget,
        reason: '${spec.id} has no legend chip',
      );
    }

    await teardown(tester);
  });

  testWidgets('the most recent crossing is named in words', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
    });

    await openDetail(tester, valley);

    // The series turns upward, so whichever crossover fired last fired up.
    expect(
      find.textContaining(RegExp(r'(Golden Cross|crossed above MA200)')),
      findsOneWidget,
    );
    expect(find.textContaining('ago'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('a crossover chip toggles its markers off', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
    });

    await openDetail(tester, valley);

    final chart = tester.widget<PriceChart>(find.byType(PriceChart));
    expect(chart.markers, isNotEmpty);

    for (final spec in crossoverSpecs) {
      await tester.ensureVisible(find.text(spec.label));
      await tester.tap(find.text(spec.label));
      await tester.pumpAndSettle();
    }

    final off = tester.widget<PriceChart>(find.byType(PriceChart));
    expect(off.markers, isEmpty);

    await teardown(tester);
  });

  testWidgets('a range too short for MA200 shows no crossings, not a crash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '["AAPL"]',
    });

    await openDetail(tester, [for (var i = 0; i < 40; i++) 100 + i.toDouble()]);

    final chart = tester.widget<PriceChart>(find.byType(PriceChart));
    expect(chart.markers, isEmpty);
    // The chips stay, reading as unavailable rather than disappearing.
    for (final spec in crossoverSpecs) {
      expect(find.text(spec.label), findsOneWidget);
    }
    expect(find.textContaining('ago'), findsNothing);

    await teardown(tester);
  });

  testWidgets('import and settings live in the overflow menu', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Import portfolio'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Import portfolio'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('the settings screen is reachable and saves a project', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://claude.ai/project/abc123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved'), findsOneWidget);
    expect(
      await WatchlistStorage().loadClaudeProjectUrl(),
      'https://claude.ai/project/abc123',
    );

    await teardown(tester);
  });

  testWidgets('the settings screen refuses a link that is not a project', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(appWith(feedResolving()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'https://example.com/hi');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Refused rather than stored: sending the button somewhere arbitrary
    // would be worse than falling back to a new chat.
    expect(find.textContaining('not a Claude project link'), findsOneWidget);
    expect(await WatchlistStorage().loadClaudeProjectUrl(), isNull);

    await teardown(tester);
  });
}
