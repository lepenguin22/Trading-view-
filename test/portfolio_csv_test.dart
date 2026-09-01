import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/portfolio_csv.dart';

/// The parser returns holdings; most of these tests are about which tickers
/// came out, so they compare symbols and leave quantities to their own group.
List<String> symbolsIn(String csv) => [
  for (final h in parseHoldingsCsv(csv)) h.symbol,
];

void main() {
  // Mirrors the layout of a real portfolio sheet — a note row above the
  // header, the table starting at column B rather than A, and a second table
  // of closed positions further down the same tab. The tickers are synthetic:
  // a fixture is not the place for someone's actual holdings.
  final sheet = File('test/fixtures/portfolio.csv').readAsStringSync();

  group('parseHoldingsCsv', () {
    test('reads the holdings table, not the closed positions below it', () {
      final symbols = symbolsIn(sheet);

      expect(symbols, ['AAA', 'BBB', 'CCC', 'DDD.L', 'BRK-B']);
      // The realised-P/L table sits under a "Stock" header further down. It is
      // the whole reason this parser stops at a blank row.
      expect(symbols, isNot(contains('ZZZ')));
      expect(symbols, isNot(contains('YYY')));
      expect(symbols, isNot(contains('XXX')));
    });

    test('does not mistake the overview totals for tickers', () {
      final symbols = symbolsIn(sheet);
      expect(symbols.any((s) => s.contains('24')), isFalse);
      expect(symbols, isNot(contains('OVERVIEW')));
    });

    test('finds the header even though it is not the first row or column', () {
      // Three rows of preamble and a leading blank column in the fixture.
      expect(symbolsIn(sheet).first, 'AAA');
    });

    test('upper-cases a lower-case ticker', () {
      // Hand-maintained sheets have entries like "tsm".
      expect(symbolsIn(sheet), contains('CCC'));
    });

    test('keeps exchange suffixes and class dashes intact', () {
      final symbols = symbolsIn(sheet);
      expect(symbols, contains('DDD.L'));
      expect(symbols, contains('BRK-B'));
    });

    test('accepts Symbol as the header name too', () {
      const csv = 'Symbol,Shares\nAAPL,10\nMSFT,5\n';
      expect(symbolsIn(csv), ['AAPL', 'MSFT']);
    });

    test('drops duplicates but keeps sheet order', () {
      const csv = 'Ticker\nMSFT\nAAPL\nMSFT\nNVDA\n';
      expect(symbolsIn(csv), ['MSFT', 'AAPL', 'NVDA']);
    });

    test('handles quoted fields containing commas', () {
      const csv = 'Ticker,Name,Value\nAAPL,"Apple, Inc.","1,234.56"\n';
      expect(symbolsIn(csv), ['AAPL']);
    });

    test('handles CRLF line endings, which is what Sheets exports', () {
      const csv = 'Ticker,Shares\r\nAAPL,10\r\nMSFT,5\r\n';
      expect(symbolsIn(csv), ['AAPL', 'MSFT']);
    });

    test('returns empty when there is no ticker column to find', () {
      // Better to report "no column found" than to guess at some other column
      // and import nonsense.
      const csv = 'Name,Value\nSomething,10\n';
      expect(symbolsIn(csv), isEmpty);
    });

    test('never matches a Stock header on its own', () {
      // The closed-positions table is headed "Stock"; matching it would import
      // sold holdings.
      const csv = 'Stock,P/L\nTSLA,-100\n';
      expect(symbolsIn(csv), isEmpty);
    });

    test('survives empty and malformed input', () {
      expect(symbolsIn(''), isEmpty);
      expect(symbolsIn('   '), isEmpty);
      expect(symbolsIn('Ticker\n'), isEmpty);
    });
  });

  group('share counts', () {
    test('reads the quantity column from the real sheet layout', () {
      // The fixture's column is headed "Shares bought", not "Shares" — which
      // is exactly why the match is on the leading word.
      final holdings = parseHoldingsCsv(sheet);

      expect(
        {for (final h in holdings) h.symbol: h.shares},
        {'AAA': 10.0, 'BBB': 5.0, 'CCC': 20.0, 'DDD.L': 40.0, 'BRK-B': 100.0},
      );
    });

    test('a sheet with no quantity column still imports, without counts', () {
      const csv = 'Ticker,Name\nAAPL,Apple\nMSFT,Microsoft\n';
      final holdings = parseHoldingsCsv(csv);

      expect([for (final h in holdings) h.symbol], ['AAPL', 'MSFT']);
      expect(holdings.every((h) => h.shares == null), isTrue);
    });

    test('never reads a money column as a quantity', () {
      // "Value of shares" mentions shares but holds currency. Reading it as a
      // count would multiply a value by a price.
      const csv = 'Ticker,Value of shares\nAAPL,"12,500.00"\n';

      expect(parseHoldingsCsv(csv).single.shares, isNull);
    });

    test('accepts the header spellings sheets actually use', () {
      for (final header in [
        'Shares',
        'Shares bought',
        'Shares held',
        'Quantity',
        'Quantity owned',
        'Qty',
        'Units',
        'No. of Shares',
        'number of shares',
      ]) {
        expect(
          parseHoldingsCsv('Ticker,$header\nAAPL,10\n').single.shares,
          10,
          reason: '"$header" should mark the quantity column',
        );
      }
    });

    test('an unreadable quantity is null, never zero', () {
      // A zero would value a real position at nothing, which is worse than
      // admitting the count is unknown.
      const csv = 'Ticker,Shares\nAAPL,\nMSFT,n/a\nNVDA,—\n';

      expect(parseHoldingsCsv(csv).every((h) => h.shares == null), isTrue);
    });

    test('a blank quantity does not end the table', () {
      // Only a blank *ticker* ends it. A holding whose count was left out is
      // still held.
      const csv = 'Ticker,Shares\nAAPL,\nMSFT,5\n';
      final holdings = parseHoldingsCsv(csv);

      expect([for (final h in holdings) h.symbol], ['AAPL', 'MSFT']);
      expect(holdings.last.shares, 5);
    });
  });

  group('cost basis', () {
    test('reads the average-cost column from the real sheet layout', () {
      // The fixture's column is headed "Average price bought  (US)", with a
      // double space and a currency note.
      final holdings = parseHoldingsCsv(sheet);

      expect(
        {for (final h in holdings) h.symbol: h.costPerShare},
        {'AAA': 100.0, 'BBB': 200.0, 'CCC': 50.0, 'DDD.L': 25.0, 'BRK-B': 10.0},
      );
    });

    test('never reads the live price as a cost', () {
      // "Current Stock Price" sits two columns from the cost in the fixture.
      // Reading it would report every position as having no gain at all.
      final aaa = parseHoldingsCsv(sheet).first;

      expect(aaa.costPerShare, 100.0);
      expect(aaa.costPerShare, isNot(110.0));
    });

    test('never reads a total-cost column as a price per share', () {
      // "Principal invested" is the whole position. Treating it as a unit
      // price would overstate the cost by a factor of the share count.
      const csv = 'Ticker,Shares,Principal invested\nAAPL,10,"1,000.00"\n';

      expect(parseHoldingsCsv(csv).single.costPerShare, isNull);
    });

    test('a column is claimed by one meaning only', () {
      // Both kinds match on a leading word, so a sheet must not be able to
      // have one column read as quantity and price at once.
      const csv = 'Ticker,Shares bought,Average price\nAAPL,10,50\n';
      final holding = parseHoldingsCsv(csv).single;

      expect(holding.shares, 10);
      expect(holding.costPerShare, 50);
    });

    test('accepts the header spellings sheets actually use', () {
      for (final header in [
        'Cost',
        'Cost basis',
        'Average price',
        'Average price bought (US)',
        'Avg cost',
        'Buy price',
        'Purchase price',
        'Price paid',
      ]) {
        expect(
          parseHoldingsCsv('Ticker,Shares,$header\nAAPL,10,50\n')
              .single
              .costPerShare,
          50,
          reason: '"$header" should mark the cost column',
        );
      }
    });

    test('a sheet with no cost column still imports, without a cost', () {
      const csv = 'Ticker,Shares\nAAPL,10\n';
      final holding = parseHoldingsCsv(csv).single;

      expect(holding.shares, 10);
      expect(holding.costPerShare, isNull);
      expect(holding.costBasis, isNull);
      expect(holding.gainAt(200), isNull);
    });
  });

  group('parseMoney', () {
    test('strips currency marks a sheet writes prices with', () {
      expect(parseMoney(r'$100.00'), 100);
      expect(parseMoney('£1,250.50'), 1250.50);
      expect(parseMoney('USD 42'), 42);
    });

    test('rejects a zero or negative cost', () {
      // A zero cost would report the whole position as pure profit.
      expect(parseMoney('0'), isNull);
      expect(parseMoney('0.00'), isNull);
      expect(parseMoney('-10'), isNull);
    });

    test('rejects anything that is not a number', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('n/a'), isNull);
      expect(parseMoney('—'), isNull);
    });
  });

  group('parseShares', () {
    test('reads plain and thousands-separated numbers', () {
      expect(parseShares('10'), 10);
      expect(parseShares('1,250'), 1250);
      expect(parseShares(' 42 '), 42);
    });

    test('keeps fractional shares', () {
      expect(parseShares('0.5'), 0.5);
      expect(parseShares('12.3456'), 12.3456);
    });

    test('reads a short position, in either notation', () {
      expect(parseShares('-100'), -100);
      expect(parseShares('(100)'), -100);
    });

    test('rejects anything that is not a number', () {
      expect(parseShares(''), isNull);
      expect(parseShares('   '), isNull);
      expect(parseShares('n/a'), isNull);
      expect(parseShares('ten'), isNull);
      expect(parseShares('\$1,000'), isNull);
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
