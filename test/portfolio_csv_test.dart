import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/portfolio_csv.dart';

void main() {
  // Mirrors the layout of a real portfolio sheet — a note row above the
  // header, the table starting at column B rather than A, and a second table
  // of closed positions further down the same tab. The tickers are synthetic:
  // a fixture is not the place for someone's actual holdings.
  final sheet = File('test/fixtures/portfolio.csv').readAsStringSync();

  group('parseHoldingsCsv', () {
    test('reads the holdings table, not the closed positions below it', () {
      final symbols = parseHoldingsCsv(sheet);

      expect(symbols, ['AAA', 'BBB', 'CCC', 'DDD.L', 'BRK-B']);
      // The realised-P/L table sits under a "Stock" header further down. It is
      // the whole reason this parser stops at a blank row.
      expect(symbols, isNot(contains('ZZZ')));
      expect(symbols, isNot(contains('YYY')));
      expect(symbols, isNot(contains('XXX')));
    });

    test('does not mistake the overview totals for tickers', () {
      final symbols = parseHoldingsCsv(sheet);
      expect(symbols.any((s) => s.contains('24')), isFalse);
      expect(symbols, isNot(contains('OVERVIEW')));
    });

    test('finds the header even though it is not the first row or column', () {
      // Three rows of preamble and a leading blank column in the fixture.
      expect(parseHoldingsCsv(sheet).first, 'AAA');
    });

    test('upper-cases a lower-case ticker', () {
      // Hand-maintained sheets have entries like "tsm".
      expect(parseHoldingsCsv(sheet), contains('CCC'));
    });

    test('keeps exchange suffixes and class dashes intact', () {
      final symbols = parseHoldingsCsv(sheet);
      expect(symbols, contains('DDD.L'));
      expect(symbols, contains('BRK-B'));
    });

    test('accepts Symbol as the header name too', () {
      const csv = 'Symbol,Shares\nAAPL,10\nMSFT,5\n';
      expect(parseHoldingsCsv(csv), ['AAPL', 'MSFT']);
    });

    test('drops duplicates but keeps sheet order', () {
      const csv = 'Ticker\nMSFT\nAAPL\nMSFT\nNVDA\n';
      expect(parseHoldingsCsv(csv), ['MSFT', 'AAPL', 'NVDA']);
    });

    test('handles quoted fields containing commas', () {
      const csv = 'Ticker,Name,Value\nAAPL,"Apple, Inc.","1,234.56"\n';
      expect(parseHoldingsCsv(csv), ['AAPL']);
    });

    test('handles CRLF line endings, which is what Sheets exports', () {
      const csv = 'Ticker,Shares\r\nAAPL,10\r\nMSFT,5\r\n';
      expect(parseHoldingsCsv(csv), ['AAPL', 'MSFT']);
    });

    test('returns empty when there is no ticker column to find', () {
      // Better to report "no column found" than to guess at some other column
      // and import nonsense.
      const csv = 'Name,Value\nSomething,10\n';
      expect(parseHoldingsCsv(csv), isEmpty);
    });

    test('never matches a Stock header on its own', () {
      // The closed-positions table is headed "Stock"; matching it would import
      // sold holdings.
      const csv = 'Stock,P/L\nTSLA,-100\n';
      expect(parseHoldingsCsv(csv), isEmpty);
    });

    test('survives empty and malformed input', () {
      expect(parseHoldingsCsv(''), isEmpty);
      expect(parseHoldingsCsv('   '), isEmpty);
      expect(parseHoldingsCsv('Ticker\n'), isEmpty);
    });
  });

  group('normaliseTicker', () {
    test('accepts the symbol shapes the feed uses', () {
      expect(normaliseTicker('aapl'), 'AAPL');
      expect(normaliseTicker(' VOD.L '), 'VOD.L');
      expect(normaliseTicker('BRK-B'), 'BRK-B');
      expect(normaliseTicker('^FTSE'), '^FTSE');
      expect(normaliseTicker('BTC-USD'), 'BTC-USD');
    });

    test('rejects prose, totals and numbers', () {
      // Sheets are hand-maintained; stray cells must not reach the price feed.
      expect(normaliseTicker('Total invested'), isNull);
      expect(normaliseTicker(r'$5,000'), isNull);
      expect(normaliseTicker('12.00%'), isNull);
      expect(normaliseTicker('12'), isNull);
      expect(normaliseTicker(''), isNull);
      expect(normaliseTicker('   '), isNull);
    });

    test('rejects anything implausibly long for a symbol', () {
      expect(normaliseTicker('ABCDEFGHIJKLMNOPQ'), isNull);
    });
  });
}
