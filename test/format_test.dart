import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/format.dart';

void main() {
  group('formatPrice', () {
    test('formats a normal price to two decimals', () {
      // The locale decides where the symbol sits, so assert on the digits.
      expect(formatPrice(196.5, 'USD'), contains('196.50'));
    });

    test('converts pence-quoted London tickers to pounds', () {
      // GBp is not an ISO currency code, and 78.4 pence is £0.78.
      final out = formatPrice(78.4, 'GBp');
      expect(out, contains('0.78'));
      expect(out, isNot(contains('78.40')));
    });

    test('shows four decimals for sub-unit prices', () {
      expect(formatPrice(0.0432, 'USD'), contains('0.0432'));
    });

    test('renders an unknown currency code alongside the number', () {
      // intl has no symbol for these, so it uses the code itself.
      expect(formatPrice(10, 'XYZ'), contains('10.00'));
      expect(formatPrice(10, 'XYZ'), contains('XYZ'));
    });

    test('renders a dash rather than NaN', () {
      expect(formatPrice(double.nan), '—');
      expect(formatPrice(double.infinity), '—');
    });
  });

  group('formatChange and formatPercent', () {
    test('always carries an explicit sign', () {
      expect(formatChange(2.5), '+2.50');
      expect(formatChange(-2.5), '−2.50');
      expect(formatChange(0), '+0.00');
      expect(formatPercent(1.2894), '+1.29%');
      expect(formatPercent(-0.5), '−0.50%');
    });

    test('uses four decimals for sub-unit moves', () {
      expect(formatChange(0.0125), '+0.0125');
    });

    test('renders a dash rather than NaN', () {
      expect(formatChange(double.nan), '—');
      expect(formatPercent(double.nan), '—');
    });
  });

  group('formatUpdatedAt', () {
    test('is empty when nothing has been fetched yet', () {
      expect(formatUpdatedAt(null), '');
    });

    test('prefixes a time with "Updated"', () {
      final ms = DateTime.utc(2024, 1, 1, 12).millisecondsSinceEpoch;
      expect(formatUpdatedAt(ms), startsWith('Updated '));
    });
  });

  group('describeMarketState', () {
    test('maps the states the feed reports', () {
      expect(describeMarketState('REGULAR'), 'Market open');
      expect(describeMarketState('PRE'), 'Pre-market');
      expect(describeMarketState('POST'), 'After hours');
      expect(describeMarketState('CLOSED'), 'Market closed');
    });

    test('says nothing for a state it does not recognise', () {
      expect(describeMarketState(''), '');
      expect(describeMarketState('SOMETHING_NEW'), '');
    });
  });

  group('normaliseSymbol', () {
    test('upper-cases and trims user input', () {
      expect(normaliseSymbol('  aapl '), 'AAPL');
      expect(normaliseSymbol('vod.l'), 'VOD.L');
      expect(normaliseSymbol('   '), '');
    });
  });
}
