import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/api/parse.dart';
import 'package:ticker/models/types.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  final chart1d = fixture('chart-1d');
  final chart1y = fixture('chart-1y');
  final chartEmpty = fixture('chart-empty');
  final chartError = fixture('chart-error');
  final search = fixture('search');

  group('parseQuote', () {
    test('reads price, name and day change from a 1d chart payload', () {
      final q = parseQuote(chart1d, fetchedAt: 1700000000000);

      expect(q.symbol, 'AAPL');
      expect(q.name, 'Apple Inc.');
      expect(q.price, 196.5);
      expect(q.previousClose, 194);
      expect(q.change, closeTo(2.5, 1e-10));
      expect(q.changePercent, closeTo((2.5 / 194) * 100, 1e-10));
      expect(q.currency, 'USD');
      expect(q.exchange, 'NasdaqGS');
      expect(q.marketState, 'REGULAR');
      expect(q.dayHigh, 197.1);
      expect(q.dayLow, 193.8);
      expect(q.fetchedAt, 1700000000000);
    });

    test(
      'drops intervals whose close is null so the sparkline has no gaps',
      () {
        final q = parseQuote(chart1d);
        // The fixture has five timestamps; the middle close is null.
        expect(q.spark, hasLength(4));
        expect(q.spark.map((p) => p.c), [194.2, 195, 195.8, 196.5]);
        expect(q.spark.every((p) => p.t > 0), isTrue);
      },
    );

    test('falls back to the symbol when no long or short name is present', () {
      expect(parseQuote(chartEmpty).name, 'ZZZZ');
    });

    test('still produces a quote when the series is empty', () {
      // A thinly traded ticker can return meta with no intraday bars at all.
      final q = parseQuote(chartEmpty);
      expect(q.price, 1.23);
      expect(q.spark, isEmpty);
    });

    test('raises a FeedException carrying the upstream description', () {
      expect(
        () => parseQuote(chartError),
        throwsA(
          isA<FeedException>().having(
            (e) => e.message,
            'message',
            'No data found, symbol may be delisted',
          ),
        ),
      );
    });

    test('raises a FeedException on a structurally unusable payload', () {
      expect(
        () => parseQuote(<String, dynamic>{}),
        throwsA(isA<FeedException>()),
      );
      expect(() => parseQuote(null), throwsA(isA<FeedException>()));
      expect(
        () => parseQuote({
          'chart': {'result': <dynamic>[]},
        }),
        throwsA(isA<FeedException>()),
      );
    });
  });

  group('parseHistory', () {
    test('carries the daily bars, symbol and currency', () {
      final h = parseHistory(chart1d);
      expect(h.symbol, 'AAPL');
      expect(h.currency, 'USD');
      // Five timestamps with one null gap across every series.
      expect(h.candles, hasLength(4));
      expect(h.candles.first.open, 194.0);
      expect(h.candles.last.close, 196.5);
    });

    test('exposes closes for the indicators and the line view', () {
      expect(parseHistory(chart1d).closes, [194.2, 195.0, 195.8, 196.5]);
    });

    test('reads a non-USD series without rescaling it', () {
      final h = parseHistory(chart1y);
      expect(h.symbol, 'VOD.L');
      expect(h.currency, 'GBp');
      expect(h.candles, hasLength(3));
      expect(h.closes, [70.0, 74.0, 78.4]);
    });

    test('raises rather than returning an empty chart', () {
      expect(() => parseHistory(chartEmpty), throwsA(isA<FeedException>()));
    });
  });

  group('parseCandles', () {
    test('reads full OHLC bars from a chart payload', () {
      final candles = parseCandles(
        (chart1d as Map<String, dynamic>)['chart']['result'][0]
            as Map<String, dynamic>,
      );

      // Five timestamps, one of which is a null gap across every series.
      expect(candles, hasLength(4));
      expect(candles.first.open, 194.0);
      expect(candles.first.high, 194.6);
      expect(candles.first.low, 193.8);
      expect(candles.first.close, 194.2);
      expect(candles.last.close, 196.5);
    });

    test('drops a bar missing any of its four values', () {
      // A close alone is not a candle: open, high and low are never invented.
      final candles = parseCandles({
        'timestamp': [1, 2, 3],
        'indicators': {
          'quote': [
            {
              'open': [10, null, 12],
              'high': [11, 12, 13],
              'low': [9, 10, 11],
              'close': [10.5, 11.5, 12.5],
            },
          ],
        },
      });
      expect(candles.map((c) => c.t), [1, 3]);
    });

    test('stops at the shortest of the parallel arrays', () {
      final candles = parseCandles({
        'timestamp': [1, 2, 3],
        'indicators': {
          'quote': [
            {
              'open': [1, 2, 3],
              'high': [2, 3, 4],
              'low': [0, 1],
              'close': [1.5, 2.5, 3.5],
            },
          ],
        },
      });
      expect(candles, hasLength(2));
    });

    test('is empty when the payload carries no OHLC at all', () {
      expect(parseCandles(<String, dynamic>{}), isEmpty);
      expect(
        parseCandles({
          'timestamp': [1, 2],
        }),
        isEmpty,
      );
    });
  });

  group('candle direction', () {
    test('an up bar closes at or above its open', () {
      expect(
        const Candle(t: 0, open: 10, high: 12, low: 9, close: 11).isUp,
        isTrue,
      );
      // A doji counts as up, matching the usual charting convention.
      expect(
        const Candle(t: 0, open: 10, high: 12, low: 9, close: 10).isUp,
        isTrue,
      );
      expect(
        const Candle(t: 0, open: 10, high: 12, low: 9, close: 9.5).isUp,
        isFalse,
      );
    });
  });

  group('parsePoints', () {
    test('stops at the shorter of the timestamp and close arrays', () {
      final points = parsePoints({
        'timestamp': [1, 2, 3],
        'indicators': {
          'quote': [
            {
              'close': [10, 11],
            },
          ],
        },
      });
      expect(points, [
        const PricePoint(t: 1, c: 10),
        const PricePoint(t: 2, c: 11),
      ]);
    });

    test('returns an empty series when indicators are missing entirely', () {
      expect(
        parsePoints({
          'timestamp': [1, 2],
        }),
        isEmpty,
      );
      expect(parsePoints(<String, dynamic>{}), isEmpty);
    });
  });

  group('parseSearch', () {
    test('keeps tradable securities and drops options and editorial hits', () {
      expect(parseSearch(search).map((r) => r.symbol), [
        'AAPL',
        'AAPL.MX',
        'IYW',
        'BTC-USD',
      ]);
    });

    test('prefers the long name and the display exchange', () {
      final results = parseSearch(search);
      expect(results[0].symbol, 'AAPL');
      expect(results[0].name, 'Apple Inc.');
      expect(results[0].exchange, 'NASDAQ');
      expect(results[0].type, 'EQUITY');
      // AAPL.MX has no longname, so the short name stands in.
      expect(results[1].name, 'Apple Inc.');
      expect(results[1].exchange, 'Mexico');
    });

    test('returns an empty list for a malformed payload', () {
      expect(parseSearch(<String, dynamic>{}), isEmpty);
      expect(parseSearch(null), isEmpty);
      expect(parseSearch({'quotes': 'nope'}), isEmpty);
    });
  });
}
