import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ticker/api/valuation_source.dart';
import 'package:ticker/api/yahoo.dart' show NetworkException;
import 'package:ticker/models/valuation.dart';

void main() {
  group('verdictFor', () {
    test('classifies a discount to fair value', () {
      // 60 against a 100 fair value is a 40% discount.
      expect(verdictFor(60, 100), ValuationVerdict.significantlyUndervalued);
      expect(verdictFor(85, 100), ValuationVerdict.undervalued);
    });

    test('treats a small gap as fair rather than a signal', () {
      // A DCF is a projection; a few percent either way is noise, and calling
      // it under- or overvalued would lend the number false authority.
      expect(verdictFor(95, 100), ValuationVerdict.fairlyValued);
      expect(verdictFor(105, 100), ValuationVerdict.fairlyValued);
      expect(verdictFor(100, 100), ValuationVerdict.fairlyValued);
    });

    test('classifies a premium to fair value', () {
      expect(verdictFor(120, 100), ValuationVerdict.overvalued);
      expect(verdictFor(160, 100), ValuationVerdict.significantlyOvervalued);
    });

    test('is null when the fair value cannot support a ratio', () {
      // Negative projected cash flows are a real outcome; treating one as
      // "undervalued at any price" would be exactly backwards.
      expect(verdictFor(50, 0), isNull);
      expect(verdictFor(50, -10), isNull);
      expect(verdictFor(double.nan, 100), isNull);
      expect(verdictFor(50, double.infinity), isNull);
    });
  });

  group('marginOfSafety', () {
    test('is positive at a discount and negative at a premium', () {
      expect(marginOfSafety(75, 100), closeTo(25, 1e-9));
      expect(marginOfSafety(125, 100), closeTo(-25, 1e-9));
      expect(marginOfSafety(100, 100), closeTo(0, 1e-9));
    });

    test('is null on an unusable fair value', () {
      expect(marginOfSafety(50, 0), isNull);
    });
  });

  group('isStale', () {
    Valuation aged(Duration age) => Valuation(
      symbol: 'AAPL',
      dcf: 100,
      currency: 'USD',
      fetchedAt: DateTime.now().subtract(age).millisecondsSinceEpoch,
    );

    test('a fresh valuation is not refetched', () {
      expect(isStale(aged(const Duration(days: 1))), isFalse);
      expect(isStale(aged(const Duration(days: 6, hours: 23))), isFalse);
    });

    test('expires after the cache window', () {
      expect(isStale(aged(const Duration(days: 8))), isTrue);
    });
  });

  group('parseValuation', () {
    test('reads the legacy dcf field', () {
      final v = parseValuation(
        '[{"symbol":"AAPL","date":"2026-08-01","dcf":152.34,'
            '"Stock Price":185.92}]',
        'AAPL',
      );
      expect(v.symbol, 'AAPL');
      expect(v.dcf, 152.34);
    });

    test('reads the newer equityValuePerShare field', () {
      // Written to accept both shapes: the live service could not be reached
      // from the build environment to confirm which one it returns.
      final v = parseValuation(
        '[{"symbol":"MSFT","equityValuePerShare":410.5}]',
        'MSFT',
      );
      expect(v.dcf, 410.5);
    });

    test('accepts a bare object as well as a single-element list', () {
      expect(parseValuation('{"symbol":"AAPL","dcf":10}', 'AAPL').dcf, 10);
    });

    test('accepts a number quoted as a string', () {
      expect(parseValuation('[{"dcf":"123.45"}]', 'AAPL').dcf, 123.45);
    });

    test('reports an unknown symbol rather than inventing a value', () {
      // The endpoint answers an unknown ticker with an empty list, not a 404.
      expect(
        () => parseValuation('[]', 'ZZZZ'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('No valuation published for ZZZZ'),
          ),
        ),
      );
    });

    test('surfaces a provider error delivered with a 200', () {
      expect(
        () => parseValuation('{"Error Message":"Invalid API KEY."}', 'AAPL'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('Invalid API KEY'),
          ),
        ),
      );
    });

    test('rejects a non-positive valuation instead of showing it', () {
      // Every ratio built on a zero or negative fair value is meaningless.
      expect(
        () => parseValuation('[{"dcf":0}]', 'AAPL'),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => parseValuation('[{"dcf":-12.5}]', 'AAPL'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('rejects a body that is not JSON', () {
      expect(
        () => parseValuation('<html>nope</html>', 'AAPL'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('ValuationSource.fetch', () {
    ValuationSource sourceReturning(String body, {int status = 200}) =>
        ValuationSource(
          client: MockClient(
            (_) async => http.Response(
              body,
              status,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );

    test('refuses to call out without a key', () async {
      var called = false;
      final source = ValuationSource(
        client: MockClient((_) async {
          called = true;
          return http.Response('[]', 200);
        }),
      );
      await expectLater(
        source.fetch('AAPL', '  '),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('No API key'),
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('sends the symbol and key on the documented path', () async {
      late Uri seen;
      final source = ValuationSource(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response('[{"dcf":1}]', 200);
        }),
      );
      await source.fetch('BRK-B', 'secret-key');

      expect(seen.path, '/api/v3/discounted-cash-flow/BRK-B');
      expect(seen.queryParameters['apikey'], 'secret-key');
    });

    test('explains a rejected key', () async {
      await expectLater(
        sourceReturning('', status: 401).fetch('AAPL', 'bad'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });

    test('explains the daily rate limit', () async {
      await expectLater(
        sourceReturning('', status: 429).fetch('AAPL', 'k'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('rate limit'),
          ),
        ),
      );
    });

    test('turns a network failure into something actionable', () async {
      final source = ValuationSource(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        source.fetch('AAPL', 'k'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
    });
  });
}
