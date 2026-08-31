import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ticker/state/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('purgeObsoleteStorage', () {
    test('clears the API key the removed fair-value feature stored', () async {
      SharedPreferences.setMockInitialValues({
        'ticker.valuation.apiKey.v1': 'a-real-key',
        'ticker.valuation.cache.v1': '{"AAPL":{"dcf":200}}',
      });

      await purgeObsoleteStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('ticker.valuation.apiKey.v1'), isFalse);
      expect(prefs.containsKey('ticker.valuation.cache.v1'), isFalse);
    });

    test('leaves the keys the app still uses alone', () async {
      SharedPreferences.setMockInitialValues({
        'ticker.watchlist.symbols.v1': '["AAPL"]',
        'ticker.portfolio.symbols.v1': '["MSFT"]',
        'ticker.valuation.apiKey.v1': 'a-real-key',
      });

      await purgeObsoleteStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ticker.watchlist.symbols.v1'), '["AAPL"]');
      expect(prefs.getString('ticker.portfolio.symbols.v1'), '["MSFT"]');
      expect(prefs.containsKey('ticker.valuation.apiKey.v1'), isFalse);
    });

    test('is a no-op on a device that never had a key', () async {
      SharedPreferences.setMockInitialValues({});

      await purgeObsoleteStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
