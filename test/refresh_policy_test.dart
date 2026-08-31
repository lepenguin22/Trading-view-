import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/state/refresh_policy.dart';

void main() {
  RefreshPlan plan({
    Duration sinceList = Duration.zero,
    Duration sinceFocus = Duration.zero,
    String? focusSymbol,
    bool marketOpen = true,
  }) => planRefresh(
    sinceList: sinceList,
    sinceFocus: sinceFocus,
    focusSymbol: focusSymbol,
    marketOpen: marketOpen,
  );

  group('planRefresh', () {
    test('does nothing when neither clock is due', () {
      expect(plan(sinceList: const Duration(seconds: 5)).isIdle, isTrue);
    });

    test('refreshes the whole list on its interval while open', () {
      expect(
        plan(sinceList: listIntervalOpen),
        const RefreshPlan(refreshList: true),
      );
    });

    test('backs the list off when every market is shut', () {
      // A minute is due while open, but not once trading has stopped.
      expect(
        plan(sinceList: listIntervalOpen, marketOpen: false).isIdle,
        isTrue,
      );
      expect(
        plan(sinceList: listIntervalClosed, marketOpen: false),
        const RefreshPlan(refreshList: true),
      );
    });

    test('polls the focused symbol faster than the list', () {
      expect(
        plan(sinceFocus: focusInterval, focusSymbol: 'AAPL'),
        const RefreshPlan(refreshSymbol: 'AAPL'),
      );
      // And not before its own interval is up.
      expect(
        plan(
          sinceFocus: const Duration(seconds: 5),
          focusSymbol: 'AAPL',
        ).isIdle,
        isTrue,
      );
    });

    test('does not fast-poll a symbol whose market is shut', () {
      // Requests spent on a price that cannot move are wasted.
      expect(
        plan(
          sinceFocus: const Duration(minutes: 5),
          focusSymbol: 'AAPL',
          marketOpen: false,
        ).isIdle,
        isTrue,
      );
    });

    test('a due list refresh wins over a due focus refresh', () {
      // The list covers the focused symbol, so doing both would fetch it twice.
      expect(
        plan(
          sinceList: listIntervalOpen,
          sinceFocus: focusInterval,
          focusSymbol: 'AAPL',
        ),
        const RefreshPlan(refreshList: true),
      );
    });

    test('does nothing for a focused symbol when none is set', () {
      expect(plan(sinceFocus: const Duration(hours: 1)).isIdle, isTrue);
    });

    test('the focus interval is meaningfully faster than the list', () {
      // The whole point: one symbol on screen updates several times per
      // whole-list poll, without multiplying the request count.
      expect(focusInterval, lessThan(listIntervalOpen));
      expect(refreshTick, lessThanOrEqualTo(focusInterval));
    });
  });

  group('isMarketOpen', () {
    test('is open during regular trading', () {
      expect(isMarketOpen(['REGULAR']), isTrue);
    });

    test('counts pre and post market as open', () {
      // Prices move then, and an earnings reaction deserves the same cadence.
      expect(isMarketOpen(['PRE']), isTrue);
      expect(isMarketOpen(['POST']), isTrue);
      expect(isMarketOpen(['POSTPOST']), isTrue);
    });

    test('is closed only when every tracked market is', () {
      expect(isMarketOpen(['CLOSED']), isFalse);
      expect(isMarketOpen(['CLOSED', 'CLOSED']), isFalse);
      // One open market anywhere is enough to keep the fast cadence.
      expect(isMarketOpen(['CLOSED', 'REGULAR']), isTrue);
    });

    test('assumes open before anything has been fetched', () {
      // Otherwise a cold start would sit idle instead of fetching.
      expect(isMarketOpen(const []), isTrue);
      expect(isMarketOpen(['']), isTrue);
    });

    test('ignores case from the feed', () {
      expect(isMarketOpen(['regular']), isTrue);
    });
  });
}
