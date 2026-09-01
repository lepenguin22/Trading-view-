# Portfolio Alerts

A mobile app for tracking your portfolio and watchlist, with price alerts.
Built with Flutter, so one Dart codebase runs on both iOS and Android.

## What it does

- **Two lists, side by side** — a **Watchlist** of symbols you chose to follow,
  and a **Portfolio** mirrored from your spreadsheet, with each holding's size,
  market value and return since purchase, and a total above the list. Both show live price,
  absolute and percentage day change, and a sparkline of the session. Pull to
  refresh; both re-poll together while the app is on screen, on the adaptive
  cadence described below.
- **Search** — find a company, fund or index by name or ticker. Covers global
  exchanges (`AAPL`, `VOD.L`, `BMW.DE`, `BTC-USD`, `^FTSE`).
- **Detail** — a daily candlestick chart you pinch to zoom and drag to pan,
  with a long press to read a bar's open, high, low and close. Plus previous
  close, day high/low and exchange. A line view is a tap away for reading the
  shape of a long span.
- **Indicators** — 20, 50 and 200 simple moving averages overlaid on the price,
  each toggleable from the legend, and a 14-period RSI in its own pane.
- **Crossovers** — Golden and Death Crosses (50/200) and price crossing MA200,
  marked on the chart and named in words, each toggleable from the legend.
- **Import** — fill the Portfolio list from a spreadsheet published as CSV,
  rather than typing holdings one by one.
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
listed symbol with under 200 days of history cannot support MA200; the legend
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

The **Portfolio** list is filled from a spreadsheet. It is deliberately
separate from the watchlist: one is what you chose to follow, the other is what
your sheet says you own, and an import rewrites the second without touching the
first. A symbol may sit on both.

The import works like this. Publish the tab holding your
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

**An import mirrors the sheet rather than merging into it.** The Portfolio
becomes exactly what the sheet lists, so selling a holding and deleting its row
removes it from the app on the next import. Removals are reported by name
alongside additions, because a removal you did not expect is the thing most
worth noticing. The replace only happens after the sheet has been fetched and
parsed successfully, so a network failure can never empty the list.

**A ticker the price feed rejects is kept, not dropped.** The sheet is the
authority on what is held, and deleting a holding because one request failed
would be worse than showing it with an error. Those are listed by name so the
sheet can be corrected.

Removing a holding from the Portfolio inside the app hides it now, but the
sheet still decides: it returns on the next import unless it is deleted there
too.

## Moving-average crossovers

Two crossovers are marked on the detail chart, each with a legend chip that
toggles it and shows how many it found in the loaded range:

| Chip | What it marks |
| --- | --- |
| **50/200** | The 50 SMA crossing the 200 — a **Golden Cross** upward, a **Death Cross** downward |
| **Price/200** | The closing price crossing the 200 SMA |

A cross is drawn as a triangle anchored to the slower average, which is where
the crossing happens in both forms. Bullish crossings point up from below the
bar and bearish point down from above, so the two are told apart by **shape and
position, not only colour** — the up-green and down-red are close enough under
common colour vision deficiencies that colour alone would not carry it. Under
the legend, the most recent crossing is named in words and dated in calendar
days: "Golden Cross 34 days ago".

**A cross is recorded on the bar whose difference takes the opposite sign to
the last non-zero difference seen** — not merely to the previous bar's. That
distinction matters when the two series touch exactly: an equal bar is a touch,
not a cross, and comparing only against the previous bar would report a series
that touches the average and then carries on in the same direction as having
crossed it twice.

Two cases read as "nothing" for different reasons, and the chip says which. A
range shorter than 200 bars reads **n/a** — the average does not exist, so the
question cannot be answered. A range where the price simply never crossed reads
**0**, which is a real answer and often the informative one. A steadily rising
stock is the case that catches this out: by the time the 200 average exists the
price is already above it, so there is genuinely nothing to cross.

Nothing here notifies you. Crossovers are drawn from history the chart has
already fetched, so they cost no extra requests and add no background work; a
cross that happened while the app was closed is on the chart when you next open
the stock. Alerting on one would mean the background worker fetching daily
history per symbol rather than just a quote — a considerably heavier job, and
not what this does.

## Position values, cost basis and the portfolio total

If your sheet has a quantity column beside the tickers, the Portfolio tab shows
what each holding is worth and totals them above the list. Add an average-cost
column and it also shows the return since purchase, per holding and overall.

Both columns are found in the same header row as the tickers — never elsewhere
in the sheet, so the closed-positions table below cannot contribute a number.
They match on the leading word, because real sheets write "Shares bought",
"Quantity owned" and "Average price bought (US)" rather than bare labels. A
column can only mean one thing: whichever kind claims it first keeps it, so a
quantity is never also read as a price.

Two lookalike columns are deliberately refused:

- **"Value of shares"** mentions shares but holds money. Reading it as a count
  would multiply a value by a price.
- **"Principal invested"** is the cost of the whole position, not the price per
  share. Reading it as a unit cost would overstate the basis by a factor of the
  share count.

The live price is not a cost either — "Current stock price" leads with a word
no cost header does, so a position never reports a return of exactly zero
because the app compared the price against itself.

**Totals are kept per currency and never added across them.** Converting pounds
to dollars needs an exchange rate this app does not have, and one invented
number would be worse than two honest ones. A portfolio spanning exchanges gets
a block per currency, largest first.

**Nothing is quietly left out.** A holding with no share count, or one whose
quote has not arrived, cannot be valued — so it is named under the total
("2 holdings not counted") rather than silently dropped from a sum the user
would otherwise trust. An unreadable quantity is never read as zero, which
would value a real position at nothing, and a cost of zero is refused for the
same reason: it would report the position as pure profit.

**A return measured over fewer holdings than the value beside it says so.** A
holding can be valued without having a cost, so the gain line carries "of 3"
when it covers three of the four positions above it — otherwise it reads as the
whole portfolio's return when it is not. The day's move and the return since
purchase are labelled separately, because they answer different questions over
different periods.

A portfolio with no quantities at all shows **no total**, not a zero: having
nothing to value is a different statement from being worth nothing.

Share counts live on the device alongside the tickers, and are sent nowhere —
the price feed is asked about symbols, never about sizes. A portfolio saved by
an older build, before quantities existed, still loads; those holdings simply
have no count until the sheet is imported again.

## How often prices update

There is no live tick feed here. Yahoo's chart endpoint is a request-response
API and it costs **one request per symbol**, so a twenty-holding portfolio on a
sixty-second poll is already twenty requests a minute — shortening that across
the board buys a little freshness and a lot of HTTP 429s.

So the app spends its request budget where you are actually looking:

| Situation | Cadence |
| --- | --- |
| Both lists, market open | every **60s** |
| Both lists, all markets closed | every **5 min** |
| The stock whose detail screen is open | every **10s** |
| App backgrounded | polling stops; a full refresh runs on resume |

The fast poll refetches **one** symbol, not the list, so watching a stock costs
six requests a minute no matter how many holdings you own. Opening a detail
screen polls it immediately rather than waiting out an interval, and closing it
stops the fast poll. A whole-list refresh resets the focused symbol's clock too,
so the two never double up.

"Market closed" is read from the `marketState` each quote carries, so a
portfolio spanning exchanges stays on the open cadence while any one of them is
trading. Before the first quotes arrive, the market is assumed open — guessing
closed would make a cold start feel broken.

**Pull to refresh** always fetches immediately, whatever the cadence says.

Going genuinely tick-by-tick would need a streaming provider (Finnhub or
Polygon over WebSocket, both with a free tier), which means an API key, a
persistent socket and its reconnection handling. Worth doing if second-by-second
matters; the polling above is deliberately the version with no new dependencies
and no key to manage.

## How alerts work

Add one from a symbol's detail screen; manage them all from the bell in the
watchlist app bar. Three kinds:

| Kind | Condition |
| --- | --- |
| **Price** | Above or below a price you set |
| **RSI** | The 14-period RSI above or below a level, 30 and 70 being the usual marks |
| **Crossover** | A Golden Cross, Death Cross, or the price crossing MA200 |

**Price and RSI are level tests, not crossing tests.** An "above 200" alert on
a symbol already trading at 210 fires on the next check rather than waiting for
a dip and a recovery — an alert set on the wrong side would otherwise never
fire at all. The create sheet says so when the condition already holds.

**A crossover is an event test instead**, because it is not a level. It fires
on a crossing dated *at or after the alert was created*, so creating a Golden
Cross alert does not fire on a cross from last month — and a cross that
happened while the phone was off still fires at the next check, because the
crossing is dated by its bar rather than by when the check ran.

Alerts are checked in two places:

- **While the app is open**, on every list refresh, so a due **price** alert
  fires within about a minute.
- **In the background**, via `workmanager`, roughly every 15 minutes.

**RSI and crossover alerts are decided in the background check only.** A quote
carries no history, so those conditions are simply unknown in the foreground,
and an unfetched indicator must never be read as "the condition was not met".
Both are daily signals confirmed at the close, so a wait of minutes costs
nothing.

**Only the symbols carrying an indicator alert pay for history.** A list of
plain price alerts still costs one cheap quote request each; the five-year
daily fetch happens only where an RSI or crossover condition actually needs it.
One symbol's history failing does not take the check down — the other alerts
are still evaluated.

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

## The launcher icon

The icon is a bull's head with an up arrow cut from its forehead — the arrow
doubles as the animal's face marking and as the chart direction, which is what
makes it read as a bull *market* rather than just a bull. It uses the app's own
"up" green on its dark background.

The art is generated rather than hand-drawn, by `tool/make_icon.py`, which
writes the two masters in `assets/icon/`: a full-bleed square, and a
transparent foreground inset to the safe zone Android crops adaptive icons to,
so the horns are never clipped by a round mask. Every platform density comes
from those two:

```bash
python3 tool/make_icon.py     # redraw the masters
dart run flutter_launcher_icons
```

Adjusting the mark means editing the geometry in the script and re-running
both, rather than re-cutting a dozen PNGs by hand.

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
  holding.dart           A holding, its size and cost; per-currency totals
  alert.dart             PriceAlert and the pure firing logic (unit tested)
  crossover.dart         Which crossovers exist and what they are called
lib/api/
  parse.dart             Pure parsers for the Yahoo payloads (unit tested)
  portfolio_source.dart  Fetches a published CSV sheet
  yahoo.dart             HTTP, host fallback, timeouts, error mapping
lib/state/
  refresh_policy.dart    When to poll what: pure cadence logic, no I/O
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
                         AlertSheet, PortfolioSummary
lib/utils/
  format.dart            Price, change and date formatting
  chart.dart             Line and candle geometry, zoom limits (unit tested)
  indicators.dart        Moving averages, Wilder RSI, crossings (unit tested)
  portfolio_csv.dart     Holdings, share counts and costs from CSV (tested)
lib/theme/app_theme.dart Palette, carried on ThemeData as an extension
test/                    Tests and payload fixtures
```

State is a single `ChangeNotifier` (`WatchlistModel`) exposed with `provider`.
It owns the refresh, the polling cadence and the persistence, and it observes
the app lifecycle so polling stops when the app is backgrounded. The cadence
itself lives in `lib/state/refresh_policy.dart` as a pure function, so it can
be tested without a clock, a network or a widget tree.

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
