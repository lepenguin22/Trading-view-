import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/format.dart';

void main() {
  group('formatScoredAt', () {
    final now = DateTime(2026, 9, 9);
    String at(int daysAgo) =>
        formatScoredAt(now.subtract(Duration(days: daysAgo)), now: now);

    test('reads in the units that matter at each distance', () {
      expect(at(0), 'scored today');
      expect(at(1), 'scored yesterday');
      expect(at(5), 'scored 5 days ago');
      expect(at(21), 'scored 3 weeks ago');
      expect(at(90), 'scored 3 months ago');
      expect(at(400), 'scored over a year ago');
      expect(at(800), 'scored 2 years ago');
    });

    test('a date in the future says so rather than reading as fresh', () {
      // A sheet typo of 2027 must not present as the most recent score there
      // is; negative elapsed time would otherwise format as "today".
      expect(at(-30), 'scored in the future');
    });
  });

  group('isScoreStale', () {
    final now = DateTime(2026, 9, 9);

    test('turns stale past six months, not before', () {
      expect(
        isScoreStale(now.subtract(const Duration(days: 90)), now: now),
        isFalse,
      );
      expect(
        isScoreStale(now.subtract(const Duration(days: 179)), now: now),
        isFalse,
      );
      expect(
        isScoreStale(now.subtract(const Duration(days: 200)), now: now),
        isTrue,
      );
    });
  });

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

  group('formatValue sign', () {
    test('negatives use the same minus as a signed amount', () {
      // These sit in one column on the calculator — a spending row above the
      // total it feeds — so an ASCII hyphen beside a typographic minus reads
      // as a different kind of number.
      expect(formatValue(-460, 'USD'), '\u2212\$460.00');
      expect(formatSignedValue(-460, 'USD'), '\u2212\$460.00');
      expect(formatValue(460, 'USD'), '\$460.00');
    });
  });
}
