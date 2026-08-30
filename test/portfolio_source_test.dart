import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ticker/api/portfolio_source.dart';
import 'package:ticker/api/yahoo.dart' show NetworkException;

void main() {
  final sheet = File('test/fixtures/portfolio.csv').readAsStringSync();

  PortfolioSource sourceReturning(
    String body, {
    int status = 200,
    String contentType = 'text/csv',
  }) => PortfolioSource(
    client: MockClient(
      (_) async =>
          http.Response(body, status, headers: {'content-type': contentType}),
    ),
  );

  const url = 'https://docs.google.com/spreadsheets/d/e/abc/pub?output=csv';

  group('parseSheetUrl', () {
    test('accepts http and https links', () {
      expect(parseSheetUrl(url), isNotNull);
      expect(parseSheetUrl('  http://example.com/a.csv  '), isNotNull);
    });

    test('rejects anything that is not a fetchable web link', () {
      expect(parseSheetUrl(''), isNull);
      expect(parseSheetUrl('not a url'), isNull);
      expect(parseSheetUrl('ftp://example.com/a.csv'), isNull);
      // A local file path would otherwise be read off the device.
      expect(parseSheetUrl('file:///etc/passwd'), isNull);
    });
  });

  group('fetchSymbols', () {
    test('returns the holdings from a published sheet', () async {
      final symbols = await sourceReturning(sheet).fetchSymbols(url);
      expect(symbols, ['AAA', 'BBB', 'CCC', 'DDD.L', 'BRK-B']);
    });

    test(
      'explains a private sheet rather than reporting a raw status',
      () async {
        // Sheets answers 200 with a sign-in page when a link is not published,
        // so the body has to be inspected, not just the status code.
        await expectLater(
          sourceReturning('<!doctype html><html><body>Sign in</body></html>')
              .fetchSymbols(url),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.message,
              'message',
              contains('Publish to web'),
            ),
          ),
        );
      },
    );

    test('reports a 403 as a permissions problem', () async {
      await expectLater(
        sourceReturning('', status: 403).fetchSymbols(url),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('private'),
          ),
        ),
      );
    });

    test('reports a missing sheet', () async {
      await expectLater(
        sourceReturning('', status: 404).fetchSymbols(url),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('still published'),
          ),
        ),
      );
    });

    test('says so when there is no ticker column', () async {
      await expectLater(
        sourceReturning('Name,Value\nCash,100\n').fetchSymbols(url),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('No ticker column'),
          ),
        ),
      );
    });

    test('rejects a malformed URL before any request is made', () async {
      var called = false;
      final source = PortfolioSource(
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        source.fetchSymbols('nonsense'),
        throwsA(isA<NetworkException>()),
      );
      expect(called, isFalse);
    });

    test('refuses a response too large to be a holdings sheet', () async {
      final huge = 'Ticker\n${'AAAA\n' * 500000}';
      expect(huge.length, greaterThan(PortfolioSource.maxBytes));
      await expectLater(
        sourceReturning(huge).fetchSymbols(url),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('surfaces a network failure in words a user can act on', () async {
      final source = PortfolioSource(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        source.fetchSymbols(url),
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
