# Ticker

A mobile app for tracking the share price of publicly listed companies.
Built with Expo and React Native, so one TypeScript codebase runs on both
iOS and Android.

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
npm install
npm start
```

Then open the project on your phone with the **Expo Go** app by scanning the QR
code in the terminal. No Xcode or Android Studio needed for this.

To run on a simulator instead, use `npm run ios` or `npm run android`.

## Checks

```bash
npm test        # unit and render tests
npm run typecheck
```

## Price data

Prices come from Yahoo Finance's public endpoints:

| Purpose | Endpoint |
| --- | --- |
| Quote and price history | `/v8/finance/chart/{symbol}` |
| Symbol search | `/v1/finance/search` |

No API key or signup is needed. Two caveats worth knowing:

- **These endpoints are undocumented.** Yahoo can change or withdraw them
  without notice. All parsing is isolated in `src/api/parse.ts` and covered by
  tests, so adapting to a shape change — or swapping in a different provider —
  means editing one file.
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
App.tsx                  Providers and root
src/navigation.tsx       Stack navigator and route types
src/api/
  types.ts               Quote, History, SearchResult, range definitions
  parse.ts               Pure parsers for the Yahoo payloads (unit tested)
  yahoo.ts               fetch, host fallback, timeouts, error mapping
src/state/
  watchlist.tsx          Watchlist context: refresh, polling, add/remove/reorder
  storage.ts             AsyncStorage persistence
src/screens/             Watchlist, Search, Detail
src/components/          QuoteRow, PriceChart, Sparkline, ChangePill
src/utils/
  format.ts              Price, change and date formatting
  chart.ts               SVG path geometry (unit tested)
src/__tests__/           Tests and payload fixtures
```

Charts are drawn with plain SVG paths via `react-native-svg` rather than a
charting library — the shapes are simple and it keeps the bundle small.

## Ideas for later

- Price alerts and push notifications when a threshold is crossed
- Holdings and cost basis, so the list shows gain/loss rather than day change
- Drag-to-reorder in place of the long-press menu
- A home screen widget
