# Ticker

A mobile app for tracking the share price of publicly listed companies.
Built with Flutter, so one Dart codebase runs on both iOS and Android.

## What it does

- **Watchlist** — your symbols with live price, absolute and percentage day
  change, and a sparkline of the session. Pull to refresh; it also re-polls
  every 60 seconds while the app is on screen.
- **Search** — find a company, fund or index by name or ticker. Covers global
  exchanges (`AAPL`, `VOD.L`, `BMW.DE`, `BTC-USD`, `^FTSE`).
- **Detail** — a price chart over 1D / 1W / 1M / 3M / 1Y / 5Y that you can drag
  across to read individual points, plus previous close, day high/low and
  exchange.
- Watchlist order and contents persist between launches, and the last prices
  are cached so a cold start shows figures immediately rather than empty rows.
- Follows the system light/dark appearance.

## Running it

```bash
flutter pub get
flutter run
```

`flutter run` picks up a connected device or a running simulator/emulator; use
`flutter devices` to see what it can find. Building for iOS needs Xcode, and
for Android needs the Android SDK — `flutter doctor` will say what is missing.

## Checks

```bash
flutter test        # unit and widget tests
flutter analyze
```

## Price data

Prices come from Yahoo Finance's public endpoints:

| Purpose | Endpoint |
| --- | --- |
| Quote and price history | `/v8/finance/chart/{symbol}` |
| Symbol search | `/v1/finance/search` |

No API key or signup is needed. Two caveats worth knowing:

- **These endpoints are undocumented.** Yahoo can change or withdraw them
  without notice. All parsing is isolated in `lib/api/parse.dart` and covered
  by tests, so adapting to a shape change — or swapping in a different provider
  — means editing one file.
- **They rate limit.** Requests present a browser user agent and fall back from
  `query1` to `query2`, but a burst of refreshes can still return HTTP 429. The
  UI surfaces that as a per-symbol message rather than blanking the list.

Quotes are fetched one symbol at a time: Yahoo's batch quote endpoint now
requires a session crumb, and a per-symbol fan-out also means one delisted
ticker cannot break the whole watchlist.

Prices are indicative and may be delayed. This app is for tracking, not for
trading decisions.

## Layout

```
lib/main.dart            App root, providers and theme wiring
lib/models/
  types.dart             PricePoint, Quote, History, SearchResult, RangeKey
lib/api/
  parse.dart             Pure parsers for the Yahoo payloads (unit tested)
  yahoo.dart             HTTP, host fallback, timeouts, error mapping
lib/state/
  watchlist.dart         Watchlist model: refresh, polling, add/remove/reorder
  storage.dart           SharedPreferences persistence
lib/screens/             Watchlist, Search, Detail
lib/widgets/             QuoteRow, PriceChart, Sparkline, ChangePill
lib/utils/
  format.dart            Price, change and date formatting
  chart.dart             Chart geometry (unit tested)
lib/theme/app_theme.dart Palette, carried on ThemeData as an extension
test/                    Tests and payload fixtures
```

State is a single `ChangeNotifier` (`WatchlistModel`) exposed with `provider`.
It owns the refresh, the 60-second poll and the persistence, and it observes
the app lifecycle so polling stops when the app is backgrounded.

Charts are drawn with `CustomPainter` rather than a charting package — the
shapes are simple and it keeps the dependency list and the app size down.

## Ideas for later

- Price alerts and push notifications when a threshold is crossed
- Holdings and cost basis, so the list shows gain/loss rather than day change
- Drag-to-reorder in place of the long-press sheet
- A home screen widget
