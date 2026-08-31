/// How often the app asks the feed for prices.
///
/// Yahoo's endpoints are fetched one request per symbol, so a whole-list poll
/// costs as many requests as there are holdings. Simply shortening the
/// interval would draw HTTP 429s. Instead the cadence follows attention and
/// market state: the one symbol on screen is polled quickly, the lists slowly,
/// and nothing is polled hard when the market is shut.
library;

/// How often the timer fires. Work is decided per tick rather than by juggling
/// several timers, so there is one place that says what happens when.
const refreshTick = Duration(seconds: 5);

/// Whole-list refresh while a market is open.
const listIntervalOpen = Duration(seconds: 60);

/// Whole-list refresh when every tracked market is shut. Not stopped outright,
/// so a move into pre- or post-market is still picked up within a few minutes.
const listIntervalClosed = Duration(minutes: 5);

/// The single symbol on screen, while a market is open. One request per tick,
/// which is affordable in a way that polling the whole list this often is not.
const focusInterval = Duration(seconds: 10);

/// What a tick should do.
class RefreshPlan {
  const RefreshPlan({this.refreshList = false, this.refreshSymbol});

  /// Refetch every tracked symbol.
  final bool refreshList;

  /// Refetch just this one, when a full refresh is not due.
  final String? refreshSymbol;

  bool get isIdle => !refreshList && refreshSymbol == null;

  @override
  bool operator ==(Object other) =>
      other is RefreshPlan &&
      other.refreshList == refreshList &&
      other.refreshSymbol == refreshSymbol;

  @override
  int get hashCode => Object.hash(refreshList, refreshSymbol);

  @override
  String toString() =>
      'RefreshPlan(list: $refreshList, symbol: $refreshSymbol)';
}

/// Decides what one tick should refresh.
///
/// Pure, so the cadence can be tested without waiting in real time.
RefreshPlan planRefresh({
  required Duration sinceList,
  required Duration sinceFocus,
  required String? focusSymbol,
  required bool marketOpen,
}) {
  final listInterval = marketOpen ? listIntervalOpen : listIntervalClosed;

  // A whole-list refresh covers the focused symbol too, so it takes priority
  // and both clocks reset together.
  if (sinceList >= listInterval) return const RefreshPlan(refreshList: true);

  // Fast-polling one symbol is only worth the requests while it can move.
  if (focusSymbol != null && marketOpen && sinceFocus >= focusInterval) {
    return RefreshPlan(refreshSymbol: focusSymbol);
  }

  return const RefreshPlan();
}

/// Market states the feed reports as tradable.
///
/// Pre- and post-market count: prices move then, and a holder watching an
/// earnings reaction at 8am wants the same cadence as at midday.
const _openStates = {'REGULAR', 'PRE', 'POST', 'POSTPOST'};

bool isMarketOpen(Iterable<String> marketStates) {
  var sawAny = false;
  for (final state in marketStates) {
    if (state.isEmpty) continue;
    sawAny = true;
    if (_openStates.contains(state.toUpperCase())) return true;
  }
  // Before the first successful fetch there is nothing to go on; assuming open
  // means the app starts by fetching rather than sitting idle.
  return !sawAny;
}
