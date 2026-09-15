import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/holding.dart';
import 'package:ticker/utils/portfolio_capital.dart';

PortfolioTotal total(String currency, double value, {int priced = 3}) =>
    PortfolioTotal(
      currency: currency,
      value: value,
      dayChange: 0,
      priced: priced,
      unpriced: 0,
    );

void main() {
  group('capitalIn', () {
    test('takes the value straight when the currency already matches', () {
      // The rate is ignored rather than applied: a stray one must not scale a
      // balance that needs no conversion.
      expect(capitalIn('SGD', total('SGD', 1000), 0), 1000);
      expect(capitalIn('SGD', total('SGD', 1000), 1.28), 1000);
    });

    test('converts when it does not', () {
      expect(capitalIn('SGD', total('USD', 1000), 1.28), closeTo(1280, 0.01));
    });

    test('refuses to convert without a rate', () {
      // Null means "ask for the rate", not "worth nothing". Both currencies
      // print a bare "$", so an unconverted figure would look right and be a
      // third light — this is the case that must never fall through.
      expect(capitalIn('SGD', total('USD', 1000), 0), isNull);
      expect(capitalIn('SGD', total('USD', 1000), -1), isNull);
      expect(capitalIn('SGD', total('USD', 1000), double.nan), isNull);
    });

    test('refuses a value that is not one', () {
      expect(capitalIn('SGD', total('SGD', double.nan), 1), isNull);
      expect(capitalIn('SGD', total('SGD', -5), 1), isNull);
      // Nothing held is a real answer, not a missing one.
      expect(capitalIn('SGD', total('SGD', 0), 1), 0);
    });
  });

  group('needsConversion', () {
    test('is about the currencies, not the rate', () {
      expect(needsConversion('SGD', total('USD', 1)), isTrue);
      expect(needsConversion('SGD', total('SGD', 1)), isFalse);
    });
  });

  group('soleCurrency', () {
    test('finds the one currency a portfolio is held in', () {
      expect(soleCurrency([total('USD', 100)])?.currency, 'USD');
    });

    test('refuses to pick one when there are several', () {
      // Several currencies have no single starting figure, and the app holds
      // no rates of its own to make one. Picking the largest and calling it
      // the portfolio would be inventing an answer.
      expect(soleCurrency([total('USD', 100), total('SGD', 5000)]), isNull);
      expect(soleCurrency([]), isNull);
    });
  });
}
