import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/api/yahoo.dart';
import 'package:ticker/models/holding.dart';
import 'package:ticker/state/storage.dart';
import 'package:ticker/state/watchlist.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// A quote payload for [symbol] at [price], having opened at [previousClose].
String quote(
  String symbol,
  double price, {
  double? previousClose,
  String currency = 'USD',
}) {
  final prev = previousClose ?? price;
  return '{"chart":{"result":[{"meta":{"currency":"$currency",'
      '"symbol":"$symbol","regularMarketPrice":$price,'
      '"previousClose":$prev,"longName":"$symbol Inc",'
      '"marketState":"REGULAR"},"timestamp":[1700000000],'
      '"indicators":{"quote":[{"open":[$prev],"high":[$price],'
      '"low":[$prev],"close":[$price]}]}}],"error":null}}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Prices every symbol from [prices]; anything absent 404s.
  MockClient feed(
    Map<String, ({double price, double prev, String currency})> prices,
  ) {
    return MockClient((request) async {
      final symbol = Uri.decodeComponent(request.url.path).split('/').last;
      final row = prices[symbol];
      if (row == null) {
        return http.Response(
          '',
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        quote(
          symbol,
          row.price,
          previousClose: row.prev,
          currency: row.currency,
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  Future<WatchlistModel> modelWith(
    List<Holding> holdings,
    Map<String, ({double price, double prev, String currency})> prices,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ticker.watchlist.symbols.v1': '[]',
    });
    final model = WatchlistModel(api: YahooApi(client: feed(prices)));
    await model.start();
    await model.importPortfolio(holdings);
    return model;
  }

  group('portfolioTotals', () {
    test('sums position values and the day change', () async {
      final model = await modelWith(
        [
          const Holding(symbol: 'AAA', shares: 10),
          const Holding(symbol: 'BBB', shares: 5),
        ],
        {
          'AAA': (price: 100, prev: 90, currency: 'USD'),
          'BBB': (price: 200, prev: 210, currency: 'USD'),
        },
      );

      final totals = model.portfolioTotals;
      expect(totals.length, 1);
      // 10 x 100 + 5 x 200
      expect(totals.single.value, 2000);
      // 10 x (100 - 90) + 5 x (200 - 210)
      expect(totals.single.dayChange, closeTo(50, 0.001));
      expect(totals.single.priced, 2);
      expect(totals.single.unpriced, 0);

      model.dispose();
    });

    test('the day change percent is measured off the opening value', () async {
      final model = await modelWith(
        [const Holding(symbol: 'AAA', shares: 10)],
        {'AAA': (price: 110, prev: 100, currency: 'USD')},
      );

      // Opened at 1000, now 1100.
      expect(model.portfolioTotals.single.dayChangePercent, closeTo(10, 0.001));

      model.dispose();
    });

    test('never adds different currencies together', () async {
      final model = await modelWith(
        [
          const Holding(symbol: 'AAA', shares: 10),
          const Holding(symbol: 'BBB', shares: 2),
        ],
        {
          'AAA': (price: 100, prev: 100, currency: 'USD'),
          'BBB': (price: 300, prev: 300, currency: 'GBP'),
        },
      );

      final totals = model.portfolioTotals;
      expect(totals.length, 2);
      expect(
        {for (final t in totals) t.currency: t.value},
        {'USD': 1000.0, 'GBP': 600.0},
      );
      // Largest first, so the currency that dominates leads.
      expect(totals.first.currency, 'USD');

      model.dispose();
    });

    test('a holding with no share count is reported, not counted', () async {
      final model = await modelWith(
        [
          const Holding(symbol: 'AAA', shares: 10),
          const Holding(symbol: 'BBB'),
        ],
        {
          'AAA': (price: 100, prev: 100, currency: 'USD'),
          'BBB': (price: 999, prev: 999, currency: 'USD'),
        },
      );

      final totals = model.portfolioTotals;
      expect(totals.single.value, 1000);
      expect(totals.single.priced, 1);
      // Stated rather than silently dropped: a total short of a position the
      // user can see on the list would be a lie.
      expect(totals.single.unpriced, 1);

      model.dispose();
    });

    test('a holding with no quote yet is reported, not counted', () async {
      final model = await modelWith(
        [
          const Holding(symbol: 'AAA', shares: 10),
          const Holding(symbol: 'ZZZ', shares: 5),
        ],
        {'AAA': (price: 100, prev: 100, currency: 'USD')},
      );

      final totals = model.portfolioTotals;
      expect(totals.single.value, 1000);
      expect(totals.single.unpriced, 1);

      model.dispose();
    });

    test(
      'an unvalued holding is counted once, not once per currency',
      () async {
        final model = await modelWith(
          [
            const Holding(symbol: 'AAA', shares: 10),
            const Holding(symbol: 'BBB', shares: 2),
            const Holding(symbol: 'CCC'),
          ],
          {
            'AAA': (price: 100, prev: 100, currency: 'USD'),
            'BBB': (price: 300, prev: 300, currency: 'GBP'),
            'CCC': (price: 50, prev: 50, currency: 'USD'),
          },
        );

        expect(model.portfolioTotals.fold(0, (sum, t) => sum + t.unpriced), 1);

        model.dispose();
      },
    );

    test('an empty portfolio has no totals rather than a zero', () async {
      final model = await modelWith(const [], const {});

      // A zero would claim the portfolio is worth nothing, which is a
      // different statement from having no portfolio.
      expect(model.portfolioTotals, isEmpty);

      model.dispose();
    });

    test('a short position reduces the total', () async {
      final model = await modelWith(
        [
          const Holding(symbol: 'AAA', shares: 10),
          const Holding(symbol: 'BBB', shares: -2),
        ],
        {
          'AAA': (price: 100, prev: 100, currency: 'USD'),
          'BBB': (price: 100, prev: 100, currency: 'USD'),
        },
      );

      expect(model.portfolioTotals.single.value, 800);

      model.dispose();
    });
  });

  group('holdings storage', () {
    test('round-trips share counts', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = WatchlistStorage();

      await storage.savePortfolio([
        const Holding(symbol: 'AAA', shares: 10.5),
        const Holding(symbol: 'BBB'),
      ]);

      expect(await storage.loadPortfolio(), [
        const Holding(symbol: 'AAA', shares: 10.5),
        const Holding(symbol: 'BBB'),
      ]);
    });

    test('reads a portfolio saved before quantities existed', () async {
      // An older build wrote a bare list of symbols. Reading only the new key
      // would silently empty an upgrading user's portfolio.
      SharedPreferences.setMockInitialValues({
        'ticker.portfolio.symbols.v1': '["AAA","BBB"]',
      });

      expect(await WatchlistStorage().loadPortfolio(), [
        const Holding(symbol: 'AAA'),
        const Holding(symbol: 'BBB'),
      ]);
    });

    test(
      'keeps the old key in step, so a downgrade still finds a list',
      () async {
        SharedPreferences.setMockInitialValues({});
        await WatchlistStorage().savePortfolio([
          const Holding(symbol: 'AAA', shares: 3),
        ]);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('ticker.portfolio.symbols.v1'), '["AAA"]');
      },
    );
  });
}
