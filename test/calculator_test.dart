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
  String valueFor(WidgetTester tester, String label, {Finder? within}) {
    final labelFinder = within == null
        ? find.text(label)
        : find.descendant(of: within, matching: find.text(label));
    final rows = find.ancestor(of: labelFinder, matching: find.byType(Row));

    for (var i = 0; i < tester.widgetList(rows).length; i++) {
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

    // With no ceiling, a year of 37% on 10,000 reaches CPF. It also earns
    // 2.5% by default, so allow for a little interest on top.
    expect(valueFor(tester, 'CPF', within: projection()), startsWith(r'$44,'));
  });

  testWidgets('the ceiling caps the contribution when set', (tester) async {
    await open(tester);
    await type(tester, 'Gross monthly salary', '10000');
    await type(tester, 'Years', '1');
    await type(tester, 'CPF wage ceiling (blank for none)', '7400');

    // Contributions are 7,400 x 37% x 12 = 32,856, capped rather than the
    // 44,400 the full salary would give; the rest is 2.5% interest.
    expect(valueFor(tester, 'CPF', within: projection()), startsWith(r'$33,'));
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
