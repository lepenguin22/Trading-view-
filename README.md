# Ticker

A mobile app for tracking the share price of publicly listed companies.
Built with Flutter, so one Dart codebase runs on both iOS and Android.

## What it does

- **Watchlist** — your symbols with live price, absolute and percentage day
  change, and a sparkline of the session. Pull to refresh; it also re-polls
  every 60 seconds while the app is on screen.
- **Search** — find a company, fund or index by name or ticker. Covers global
  exchanges (`AAPL`, `VOD.L`, `BMW.DE`, `BTC-USD`, `^FTSE`).
- **Detail** — a candlestick chart over 1D / 1W / 1M / 3M / 1Y / 5Y that you
  can drag across to read each bar's open, high, low and close, plus previous
  close, day high/low and exchange. A line view is a tap away for reading the
  shape of a long range.
- **Price alerts** — set an alert on any symbol for a price rising to or above,
  or falling to or below, a level you choose. When it fires you get a
  notification, and the alert switches itself off so it does not nag.
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

## Charts

The detail screen draws candlesticks by default: a body from open to close,
green when the bar closed at or above its open and red when it closed below,
with a wick spanning the high and low. Dragging across the chart puts an
O/H/L/C readout in the header for the bar under your finger. The toggle beside
the range buttons switches to a close-price line, which is easier to read for
the overall shape of a 1Y or 5Y range.

**Bars are aggregated to fit the screen.** A phone is a few hundred pixels
wide, and a 5Y weekly series is around 260 bars — drawn one-per-point that is
an unreadable smear. Adjacent bars are merged until they fit, which is the same
operation as moving to a coarser timeframe: the merged bar opens where the
first opened, closes where the last closed, and spans the extremes between. So
a 5Y chart shows something closer to monthly bars than weekly ones. The
aggregation is pure and unit tested.

The watchlist sparklines stay simple lines — candles at 56x28 pixels would be
noise, not information.

A bar is only drawn when the feed supplies all four of open, high, low and
close. Yahoo pads its arrays with nulls for halted intervals, and inventing an
open from a close would draw a candle that never traded.

## How price alerts work

Add one from a symbol's detail screen; manage them all from the bell in the
watchlist app bar. An alert is a level test, not a crossing test — an "above
200" alert on a symbol already trading at 210 fires on the next check rather
than waiting for a dip and a recovery. The create sheet says so when the
condition already holds.

Alerts are checked in two places:

- **While the app is open**, on the existing 60-second refresh, so a due alert
  fires within about a minute.
- **In the background**, via `workmanager`, roughly every 15 minutes.

**What to expect on each platform.** On Android this works as you would hope:
WorkManager wakes the app on a fairly reliable cadence, though 15 minutes is a
floor the OS enforces and aggressive battery optimisation on some vendor ROMs
(Xiaomi, Huawei, OnePlus) can delay or suppress it. On iOS, background refresh
is opportunistic: `BGTaskScheduler` decides when your app runs based on usage
patterns and battery, so an alert may arrive hours late or not until the app is
next opened. **Do not rely on either platform for anything time-critical.**
Getting punctual alerts requires a server watching prices and pushing to the
device, which this app deliberately does not have.

Alerts fire once and then disarm. Re-arm one from the alerts screen — the
switch clears its fired state too. Background work is only scheduled while at
least one alert is armed, so a device with none does no background work at all.

Notification permission is requested when you create your first alert, rather
than at launch, so the system prompt arrives with obvious context.

## Building a signed release

The app's identity is `io.github.lepenguin22.ticker` on both platforms.

Debug and profile builds need no setup. A release build signs with the debug
key unless you supply a keystore, so `flutter run --release` works on a fresh
clone — but an APK signed that way cannot be published.

To produce a publishable build, generate a keystore once:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then copy `android/key.properties.example` to `android/key.properties` and fill
in the passwords, alias and the path to the file. Gradle picks it up
automatically:

```bash
flutter build apk        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle  # build/app/outputs/bundle/release/app-release.aab
```

`key.properties` and any `*.jks` / `*.keystore` file are gitignored. Keep the
keystore outside the repository and back it up: losing it means you can never
ship an update to an app already on the Play Store, and there is no recovery.

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
  types.dart             PricePoint, Candle, Quote, History, RangeKey
  alert.dart             PriceAlert and the pure firing logic (unit tested)
lib/api/
  parse.dart             Pure parsers for the Yahoo payloads (unit tested)
  yahoo.dart             HTTP, host fallback, timeouts, error mapping
lib/state/
  watchlist.dart         Watchlist model: refresh, polling, add/remove/reorder
  alerts.dart            Alerts model: create, arm/disarm, foreground firing
  storage.dart           SharedPreferences persistence
  alert_storage.dart     Alert persistence, shared with the background isolate
lib/background/
  alert_worker.dart      Background entry point, check routine and scheduling
lib/notifications/
  notifications.dart     Local notification channel, permission and posting
lib/screens/             Watchlist, Search, Detail, Alerts
lib/widgets/             QuoteRow, PriceChart, Sparkline, ChangePill, AlertSheet
lib/utils/
  format.dart            Price, change and date formatting
  chart.dart             Line and candle geometry, aggregation (unit tested)
lib/theme/app_theme.dart Palette, carried on ThemeData as an extension
test/                    Tests and payload fixtures
```

State is a single `ChangeNotifier` (`WatchlistModel`) exposed with `provider`.
It owns the refresh, the 60-second poll and the persistence, and it observes
the app lifecycle so polling stops when the app is backgrounded.

Charts are drawn with `CustomPainter` rather than a charting package — the
shapes are simple and it keeps the dependency list and the app size down.

One `YahooApi` is provided to the whole app, so the watchlist poll, the detail
chart and search share a single HTTP client and its connection pool.

## Ideas for later

- Server-side alert checking, so notifications are punctual rather than
  best-effort — the single biggest limitation of the current design
- Holdings and cost basis, so the list shows gain/loss rather than day change
- Drag-to-reorder in place of the long-press sheet
- A home screen widget
