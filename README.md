# Ticker

A mobile app for tracking the share price of publicly listed companies.
Built with Flutter, so one Dart codebase runs on both iOS and Android.

## What it does

- **Watchlist** — your symbols with live price, absolute and percentage day
  change, and a sparkline of the session. Pull to refresh; it also re-polls
  every 60 seconds while the app is on screen.
- **Search** — find a company, fund or index by name or ticker. Covers global
  exchanges (`AAPL`, `VOD.L`, `BMW.DE`, `BTC-USD`, `^FTSE`).
- **Detail** — a daily candlestick chart you pinch to zoom and drag to pan,
  with a long press to read a bar's open, high, low and close. Plus previous
  close, day high/low and exchange. A line view is a tap away for reading the
  shape of a long span.
- **Indicators** — 20, 50 and 100 simple moving averages overlaid on the price,
  each toggleable from the legend, and a 14-period RSI in its own pane.
- **Import** — pull your holdings in from a spreadsheet published as CSV,
  rather than typing them one by one.
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

**One candle is always one trading day.** There is no timeframe picker: the
chart fetches five years of daily bars in a single request and you choose what
to look at by zooming, the way a desktop charting tool works. Zooming changes
how many days are on screen; it never changes what a bar means.

- A **price axis** down the right-hand side, with gridlines at round values and
  a tag marking the latest close — or, while scrubbing, the close of the bar
  under your finger.
- **Pinch** to zoom, anchored on the point between your fingers.
- **Drag** to pan through history.
- **Long press and drag** for the crosshair and the O/H/L/C readout — a plain
  drag pans, so scrubbing sits behind a long press.
- Zoom buttons sit beside the chart too. A pinch is fiddly for fine
  adjustment, and the buttons are reachable by keyboard and screen reader.

The header reports the move across the **visible window**, so zooming changes
what the percentage is measured over, and the caption names the span and its
dates.

**The price axis rescales with the view.** Gridlines are placed at round
numbers — steps of 1, 2, 2.5 or 5 times a power of ten — rather than at even
divisions of whatever range happens to be on screen, so labels read 122.50
rather than 121.37. Its gutter is measured from the widest label rather than
fixed, so a four-figure price is never clipped and a two-figure one wastes no
space. The RSI pane below reserves the same gutter, which is what keeps the two
plots sharing an x-axis: an RSI trough sits under the candle that caused it.

Axis labels drop the currency symbol — it is in the header, and repeating it at
every gridline would only widen the gutter. Pence-quoted London tickers are
scaled to pounds first, so the axis agrees with the header rather than reading
7,800 where the header reads £78.00.

**How far out you can zoom is limited by legibility, not by merging bars.**
Since a bar is always a day, the chart refuses to shrink candles below about
1.6 pixels of slot — roughly 200–450 days on a phone, depending on width. To
see further back you pan rather than zoom out. Zooming in stops at 12 bars, so
a single candle can never fill the screen.

**The detail chart no longer shows intraday.** Daily bars are the whole point
of the current design, so today's tick-by-tick action is not on this screen;
the watchlist sparkline still carries the intraday session.

### Indicators

Three simple moving averages (20 / 50 / 100) are drawn over the price, and
Wilder's RSI (14) sits in a pane below it. Both are computed from the same
`lib/utils/indicators.dart`, which is pure and unit tested against
hand-computed values.

**Periods are days.** MA20 is twenty trading days, RSI(14) is fourteen — the
conventional reading, and the same regardless of zoom. Indicators are computed
over the whole fetched series and then sliced to the visible window, not
recomputed on the slice, so a 20 SMA is still correct at the left edge of the
view: it uses the twenty days before it, which are off screen but not missing.

**A period with too few bars reads `n/a` rather than disappearing.** A newly
listed symbol with under 100 days of history cannot support MA100; the legend
chip stays visible and greyed so it is clear the data is short rather than the
line silently missing.

RSI uses Wilder's smoothing — the seed is the mean of the first 14 changes and
each later bar carries `(previous * 13 + current) / 14` — which is what every
charting package means by "RSI". A simple average of gains and losses agrees on
the first value and drifts after it. One deliberate deviation: a dead-flat
series has no gains *or* losses, and the ratio is undefined; that case reads 50
(neutral) rather than the 100 the formula would imply, because calling a
motionless line "maximally overbought" would be misleading.

The RSI pane is separate from the price plot rather than overlaid on a second
y-axis. RSI is bounded 0–100 and price is not; sharing an axis would invite
reading crossings that do not exist. Its scale is pinned to 0–100 for the same
reason — auto-fitting would destroy the only thing RSI is read for, which is
where it sits against 30 and 70.

**Indicator colours were picked with a validator, not by eye.** The three MA
lines are checked for lightness, chroma, contrast, and separation on every pair
under normal, protan, deutan and tritan vision, in both light and dark. One
caveat worth stating: red/green candlesticks already occupy most of the
colour-blind-separable space — the existing up/down pair is itself marginal
under deuteranopia — so no third set of hues can be fully separable from both
candles *and* each other. The MA lines are therefore distinguished from the
candles by mark type (a thin line against a filled body) and by the legend
labelling each one directly, which is why the legend is always present.

A bar is only drawn when the feed supplies all four of open, high, low and
close. Yahoo pads its arrays with nulls for halted intervals, and inventing an
open from a close would draw a candle that never traded.

## Importing a portfolio

The watchlist can be filled from a spreadsheet. Publish the tab holding your
positions as CSV (in Sheets: **File → Share → Publish to web**, pick the single
tab, choose CSV), paste the link into the import screen, and every ticker in it
is checked against the price feed and added. The link is remembered, so
re-importing later is one tap.

**Publishing makes that tab readable by anyone with the link.** Publish only
the tab with your positions — not the whole document — and keep tabs holding
balances or salary out of it. Nothing else is exposed: no account is linked and
no token is stored, only the URL you paste.

**Only the first holdings table is read.** The parser finds a column headed
`Ticker` or `Symbol` and stops at the first blank row. Real portfolio sheets
often carry a second table of *closed* positions further down the same tab —
frequently headed `Stock` — and importing that would put shares you no longer
own onto your watchlist. `Stock` is deliberately not treated as a ticker
header.

The parser is built for hand-maintained sheets: the table need not start at row
1 or column A, tickers may be lower case, exchange suffixes and class dashes
(`VOD.L`, `BRK-B`) survive, and cells that are prose, totals or bare numbers
are dropped rather than sent to the price feed.

**Every ticker is verified before it is added.** A symbol the feed rejects is
reported by name so the sheet can be corrected, rather than landing as a dead
row. Symbols already on the watchlist are left alone, so re-importing an
unchanged sheet is a no-op.

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
| Quote and daily price history | `/v8/finance/chart/{symbol}` |
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
  types.dart             PricePoint, Candle, Quote, History, ChartWindow
  alert.dart             PriceAlert and the pure firing logic (unit tested)
lib/api/
  parse.dart             Pure parsers for the Yahoo payloads (unit tested)
  portfolio_source.dart  Fetches a published CSV sheet
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
lib/screens/             Watchlist, Search, Detail, Alerts, Import
lib/widgets/             QuoteRow, PriceChart, RsiPane, Sparkline, ChangePill,
                         AlertSheet
lib/utils/
  format.dart            Price, change and date formatting
  chart.dart             Line and candle geometry, zoom limits (unit tested)
  indicators.dart        Moving averages and Wilder RSI (unit tested)
  portfolio_csv.dart     Holdings-table extraction from CSV (unit tested)
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
