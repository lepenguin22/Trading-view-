import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/screens/calculator_screen.dart';
import 'package:ticker/state/storage.dart';
import 'package:ticker/theme/app_theme.dart';
import 'package:ticker/widgets/projection_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Opens the screen on a viewport tall enough to build every card.
  ///
  /// The screen is a lazy ListView, so on a phone-sized surface the cards
  /// below the fold are never built and scrolling to one disposes another.
  /// A tall viewport keeps the whole form live, which is what these tests are
  /// about — the arithmetic across sections, not the scrolling.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: lightTheme, home: const CalculatorScreen()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pumpAndSettle();
  }

  /// The value shown on the row labelled [label].
  ///
  /// Scoped to the row rather than searched for across the screen: two rows
  /// legitimately show the same figure — take-home equals what is left when
  /// nothing is being invested — and a bare text match cannot tell them
  /// apart.
  /// [within] scopes the search to one card. "CPF" appears three times — as a
  /// summary row, a card title and the chart's legend key — so the search
  /// takes the first row that actually carries a value beside the label,
  /// rather than the first row containing the word.
  ///
  /// Rows inside the chart are skipped. Its legend names the same accounts as
  /// the summary and carries the same figures rounded to fit, so without this
  /// the assertions would silently land on "$9.8k" instead of "$9,777.96".
  String valueFor(WidgetTester tester, String label, {Finder? within}) {
    final labelFinder = within == null
        ? find.text(label)
        : find.descendant(of: within, matching: find.text(label));
    final rows = find.ancestor(of: labelFinder, matching: find.byType(Row));

    for (var i = 0; i < tester.widgetList(rows).length; i++) {
      final inChart = find.ancestor(
        of: rows.at(i),
        matching: find.byType(ProjectionChart),
      );
      if (tester.widgetList(inChart).isNotEmpty) continue;
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: rows.at(i), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      if (texts.length >= 2 && texts.last != label) return texts.last;
    }
    fail('No row labelled "$label" carried a value.');
  }

  /// The card holding the projection summary.
  Finder projection() => find
      .ancestor(of: find.text('Projection'), matching: find.byType(Column))
      .first;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('take-home follows gross and the CPF percentage', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');

    // 4,300 less 20% employee CPF.
    expect(valueFor(tester, 'Take-home pay'), r'$3,440.00');

    await type(tester, 'Your CPF contribution', '0');
    expect(valueFor(tester, 'Take-home pay'), r'$4,300.00');
  });

  testWidgets('a plan beyond take-home says so rather than silently running', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Monthly investment', '4000');

    expect(
      find.textContaining('more than take-home pay covers'),
      findsOneWidget,
    );

    await type(tester, 'Monthly investment', '900');
    expect(find.textContaining('more than take-home pay covers'), findsNothing);
  });

  testWidgets('spending comes out before what is left over', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Average monthly spending', '1250');
    await type(tester, 'Monthly investment', '919');

    // 3,440 take-home, less 1,250 spent and 919 invested.
    expect(valueFor(tester, 'Take-home pay'), r'$3,440.00');
    expect(valueFor(tester, 'Less spending'), r'−$1,250.00');
    expect(valueFor(tester, 'Less investing'), r'−$919.00');
    expect(valueFor(tester, 'Left over'), r'$1,271.00');
  });

  testWidgets('spending alone can put a plan beyond take-home', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Monthly investment', '900');

    // Affordable on its own.
    expect(find.textContaining('more than take-home'), findsNothing);

    // And not, once the month's spending is counted — which is the case the
    // warning missed before spending was an input at all.
    await type(tester, 'Average monthly spending', '3000');
    expect(find.textContaining('more than take-home'), findsOneWidget);
    expect(valueFor(tester, 'Left over'), r'−$460.00');
  });

  testWidgets('spending is not quietly taken off the projection', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Invested today', '10000');
    await type(tester, 'Monthly investment', '500');
    await type(tester, 'Years', '10');
    final withoutSpending = valueFor(tester, 'Investments');

    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Average monthly spending', '3000');

    // How much is invested is what the user typed. Reducing it to fit the
    // budget would project a plan they never described.
    expect(valueFor(tester, 'Investments'), withoutSpending);
  });

  testWidgets('the projection grows and separates growth from contributions', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Invested today', '10000');
    await type(tester, 'Monthly investment', '500');
    await type(tester, 'Years', '10');

    expect(find.byType(ProjectionChart), findsOneWidget);
    expect(find.text('In 10 years'), findsOneWidget);
    // Paid in is 10,000 + 500 x 120.
    expect(valueFor(tester, 'Paid in'), r'$70,000.00');
    // And the total exceeds it, the difference being growth.
    expect(valueFor(tester, 'Growth'), isNot(r'$0.00'));
  });

  testWidgets('an empty ceiling means no ceiling, not a ceiling of zero', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '10000');
    await type(tester, 'Years', '1');

    // With no ceiling, a year of 23+6+8% on 10,000 reaches CPF: 44,400,
    // plus interest at each account's own rate.
    expect(
      valueFor(tester, 'CPF together', within: projection()),
      startsWith(r'$45,'),
    );
  });

  testWidgets('the ceiling caps the contribution when set', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '10000');
    await type(tester, 'Years', '1');
    await type(tester, 'CPF wage ceiling (blank for none)', '7400');

    // Contributions are 7,400 x 37% x 12 = 32,856, capped rather than the
    // 44,400 the full salary would give; the rest is interest.
    expect(
      valueFor(tester, 'CPF together', within: projection()),
      startsWith(r'$33,'),
    );
  });

  testWidgets('each CPF account is shown on its own', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '10000');
    await type(tester, 'Years', '1');

    // One month's 23/6/8 of 10,000 is 2,300 / 600 / 800, so after a year the
    // accounts are far enough apart to be told from one another — which is
    // what a single blended CPF figure hid.
    final oa = valueFor(tester, 'Ordinary Account', within: projection());
    final sa = valueFor(tester, 'Special Account', within: projection());
    final ma = valueFor(tester, 'MediSave', within: projection());

    expect(oa, startsWith(r'$27,'));
    expect(sa, startsWith(r'$7,'));
    expect(ma, startsWith(r'$9,'));

    // And the employer's share is derived, never asked for.
    expect(find.text("Employer's CPF contribution"), findsNothing);
    expect(valueFor(tester, "Employer's share"), '17% of wage');
  });

  testWidgets('an impossible employee rate is flagged, not absorbed', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    expect(find.textContaining('cannot happen'), findsNothing);

    // More out of pay than reaches CPF: the allocation and the rate are from
    // different age bands, and every CPF figure would be built on it.
    await type(tester, 'Your CPF contribution', '40');
    expect(find.textContaining('cannot happen'), findsOneWidget);
  });

  testWidgets('the four-band chart fits a narrow phone', (tester) async {
    // The legend is four keys now. It wraps rather than running off the edge —
    // a cut-off legend is worse than two rows, and a RenderFlex overflow here
    // fails the test on its own.
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: lightTheme, home: const CalculatorScreen()),
    );
    await tester.pumpAndSettle();
    await type(tester, 'Gross monthly salary', '4300');

    for (final key in ['Investments', 'MediSave', 'Special', 'Ordinary']) {
      expect(
        find.text(key),
        findsWidgets,
        reason: '"$key" should be named, not left to colour alone',
      );
    }
  });

  testWidgets('a smaller account never reads as the larger one', (
    tester,
  ) async {
    // The bug this replaces: the chart stacked the pots, so every line was a
    // running total and the Special Account — a third the size of the
    // Ordinary Account — drew *above* it. The legend now carries each line's
    // own value, which is what the lines are drawn from.
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Years', '20');

    final chart = find.byType(ProjectionChart);
    String legend(String label) {
      final row = find
          .ancestor(
            of: find.descendant(of: chart, matching: find.text(label)),
            matching: find.byType(Row),
          )
          .first;
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      return texts.last;
    }

    // 23% of wage into Ordinary against 6% into Special: Ordinary must be the
    // larger figure, and the legend must say so.
    final oa = legend('Ordinary');
    final sa = legend('Special');
    expect(oa, isNot(sa));
    expect(_thousands(oa), greaterThan(_thousands(sa)));

    // And neither is a running total: the summary below lists the same
    // account values, so the two must agree — within the rounding the legend
    // does to fit, which is why this compares numbers rather than strings.
    final exact = _money(
      valueFor(tester, 'Ordinary Account', within: projection()),
    );
    expect(_thousands(oa) * 1000, closeTo(exact, 1000));

    // The stacked chart's Ordinary line sat at the account's own value, so
    // only the accounts above it exposed the bug. Special must be nowhere
    // near Ordinary + Special, which is where its line used to be drawn.
    final exactSa = _money(
      valueFor(tester, 'Special Account', within: projection()),
    );
    expect(_thousands(sa) * 1000, closeTo(exactSa, 1000));
    expect(_thousands(sa) * 1000, lessThan(exact));
  });

  testWidgets('inputs survive leaving and returning', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '4300');
    await type(tester, 'Monthly investment', '919');

    await tester.tap(find.byTooltip('Save these inputs'));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);

    expect(
      await WatchlistStorage().loadCalculatorInputs(),
      containsPair('gross', 4300),
    );

    // A fresh screen reads them back.
    await open(tester);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Gross monthly salary'),
          )
          .controller!
          .text,
      '4300',
    );
  });

  testWidgets('an empty form does not crash or claim a projection', (
    tester,
  ) async {
    await open(tester);

    // Everything zero: the chart has nothing to draw but must not throw.
    expect(find.byType(CalculatorScreen), findsOneWidget);
    expect(find.text('In 20 years'), findsOneWidget);
  });
}

/// Reads "$341k" back to 341, so two legend figures can be ranked.
double _thousands(String compact) =>
    double.parse(compact.replaceAll(RegExp(r'[^0-9.]'), ''));

/// Reads "$307,553.99" back to a number.
double _money(String formatted) =>
    double.parse(formatted.replaceAll(RegExp(r'[^0-9.]'), ''));
