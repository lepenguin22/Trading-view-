# Portfolio Alerts

A mobile app for tracking your portfolio and watchlist, with price alerts.
Built with Flutter, so one Dart codebase runs on both iOS and Android.

## What it does

- **Two lists, side by side** — a **Watchlist** of symbols you chose to follow,
  and a **Portfolio** mirrored from your spreadsheet, with each holding's size,
  market value and return since purchase, an analysis checklist score, and a
  total above the list. Both show live price,
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

**Where the figures sit.** Share count, position value and return get a band of
their own across the full width of the row, under a hairline. Squeezed into the
left column beside the symbol and company name they shared about half the width
and ellipsised, which is no use for the numbers you actually scan the list for.
Each is its own column, so they line up down the list and can be compared
between holdings rather than read one row at a time.

Tapping a holding opens **Your position** on its detail screen: shares, average
cost, cost basis, what the position is worth, the day's move on the position,
and the total return — each as money and, where a percentage is the more
comparable figure, as both. The day's move is on the whole position rather than
on one share, because "up 1.15%" means something different at either scale. It
reads the live quote, not the scrubbed chart headline: dragging the chart asks
what the price was in the past, not what the position is worth now. Rows that
need a purchase price the sheet never gave are absent rather than shown empty.

Share counts live on the device alongside the tickers, and are sent nowhere —
the price feed is asked about symbols, never about sizes. A portfolio saved by
an older build, before quantities existed, still loads; those holdings simply
have no count until the sheet is imported again.

## The calculator

Under the overflow menu. It projects CPF and investments forward month by month
and charts them as **four lines from a shared zero** — the three CPF accounts
and investments.

**Unstacked, and that is the point.** They were stacked, which made every line a
running total: the Special Account, a third the size of the Ordinary Account,
drew its line *above* it. The value was the thickness of the band, and nobody
reads a chart that way. Four pots meant to be compared need a common baseline,
where height is the value and the eye can rank them. Nothing is lost — the total
is the headline figure above the plot, which is where it was being read from
anyway.

**Both axes are labelled.** Money runs up the left at round values — 250k, 500k,
750k — chosen with the same tick logic the price chart uses, rather than at even
fractions of the data's own maximum, which would read 308k, 616k, 925k and be
no use to anyone. The gutter is measured from the widest label, because "$1.2M"
and "$950k" are different widths and a fixed one would clip the first or waste
space on the second. Years run along the bottom, thinned to every second,
fifth or tenth as the width demands — a label per year on a twenty-year
projection is a smear, which is worse than no axis at all.

The legend carries each line's value at the point being scrubbed, rounded to fit
(`$341k`), so the lines can be ranked without measuring them against the
gridlines; the exact figures are listed in full directly below. It is always
present and wraps rather than being cut off, so identity is never carried by
colour alone.

The four series use their own validated colour set rather than borrowing the
moving-average one: four series need an order checked as four. Run through the
palette validator in both themes — worst adjacent pair ΔE 13.8 protan in light
and 14.0 in dark, against a target of 8.

Salary drives both. Gross less your CPF percentage gives take-home, and the
month is then written out as the subtraction it is:

```
Take-home pay        $3,440.00
Less spending       −$1,250.00
Less investing        −$919.00
Left over            $1,271.00
```

**Average monthly spending is an input** — rent, food, transport, insurance,
whatever the month actually costs. Without it, "what is left" was take-home
minus the investment alone, which on any real budget is a number nobody has,
and a plan could look comfortably affordable while spending had already
accounted for the money twice over. If what is left goes negative the
calculator says so rather than quietly projecting money you do not have.

**Spending does not change the projection.** How much is invested is what you
typed, not something derived from what is left over — quietly trimming the
contribution to fit the budget would project a plan you never described. What
spending decides is whether the plan is affordable, and nothing else.

**CPF is three accounts, not one.** Ordinary, Special and MediSave each get
their own opening balance, their own share of the wage, and their own interest
rate — because they do not pay the same. The Ordinary Account earns 2.5%
against 4% on Special and MediSave, and averaging them into a single rate hid
which pot was doing the work. They stack as three bands on the chart, under
investments, and appear as three rows in the summary.

### Allocation by age

Give the calculator your age and the split follows it — and keeps following it
as the projection runs. Someone 34 today spends a twenty-year projection in
three different bands, and holding the first for all twenty would overstate the
Ordinary Account for most of it.

| Age | Ordinary | Special | MediSave |
|---|---|---|---|
| 35 and below | 23% | 6% | 8% |
| above 35 to 45 | 21% | 7% | 9% |
| above 45 to 50 | 19% | 8% | 10% |
| above 50 to 55 | 15% | 11.5% | 10.5% |

Percentages of wage, for private-sector employees earning above $750 a month,
effective 1 January 2026.

The band card names the shifts the projection will cross — **"Shifts at age 36,
then 46"** for a 28-year-old over twenty years. Without it they are invisible: a
barely-perceptible kink in the chart and nothing at all in the summary, so
today's band reads as though it holds for the whole projection. A projection
that stays inside one band says *"no change in 5 years"* rather than leaving the
row empty, which would read as "unknown" instead of "none".

Note the shift lands at **36, not 35**: CPF's first band is "35 and below", so
the change falls on the birthday after it. Every band totals 37%: the bands move money between
accounts, they do not change how much reaches CPF, and a test asserts it.

The figures were cross-checked against CPF's published allocation *ratios* —
the share of the contribution rather than of the wage — which reproduce them
exactly at a 37% total: 0.5677 × 37 = 21.0, 0.4055 × 37 = 15.0,
0.3108 × 37 = 11.5, 0.2837 × 37 = 10.5.

**The table stops at 55, and says so.** Past that CPF stops working the way this
models it: the Special Account closes, contributions go to a Retirement Account
up to the Full Retirement Sum, and the total rate falls below 37%. None of that
is modelled, so a projection running past 55 carries a warning rather than
quietly producing numbers for it.

**Leaving the age blank goes back to typing the shares in by hand.** That is the
escape hatch, and it is the reason encoding this table is defensible at all:
allocation moves, this one will go stale, and when it does the shares are still
yours to set. It is the only CPF policy the app carries a number for — interest
rates, your contribution rate and the wage ceiling all stay inputs.

Shares are percentages of your wage, the form CPF publishes its allocation
tables in, so a rate looked up there goes in as written. **The employer's share
is derived, not asked for** — it is whatever reaches CPF that did not come out
of take-home pay. Two inputs that had to agree would be a rule to get wrong; if
more comes out of your pay than reaches CPF, which cannot happen, the
calculator says so rather than projecting on it.

### Starting from the portfolio

The first portfolio's card shows what the imported portfolio is currently worth
and offers to take it as **Invested today**.

**Offered, not applied.** The figure moves with every price refresh, and a
projection whose opening balance drifts under the reader is worse than one they
set deliberately. Taking it copies a number into the field, where it stays until
they take it again.

**A different currency needs a rate first.** CPF is Singapore-only, so the
projection adds both pots in one currency — and a US portfolio is not in it.
Both print a bare `$`, so an unconverted balance would look entirely correct and
be a third light. The button stays disabled until a rate is given, and the
converted figure is shown before it is taken.

**A portfolio in several currencies is refused, not guessed.** There is no
single starting figure, and the app holds no exchange rates of its own to make
one; picking the largest and calling it the portfolio would be inventing an
answer. It says so and leaves the field to you.

Holdings the total could not price are named beside the count, the same way the
portfolio summary names them — a starting balance quietly short of a position
would compound that gap for every year of the projection.

### Three investment portfolios

Three cards, each taking a name, a balance, a monthly amount and a rate.
Nothing is imported into the second and third: they are for money this app does
not track, and they are plain numbers by design.

**Each one is named**, and the name is what its card is headed with and what
its row in the summary reads — "IBKR" and "Pension" tell you something that
"Second portfolio" and "Third portfolio" do not. Those defaults are hints
rather than text, so there is nothing to clear before typing and emptying the
field hands the default straight back. Names live in the same saved blob as the
figures, written in one go, because a projection with its names one save behind
its numbers would be worse than one with neither.

**A rate per portfolio, not one rate across them.** Averaging three portfolios
into a single rate is the mistake these cards exist to avoid: a cash account at
1% and an index fund at 8% do not behave like two accounts at 4.5%, and over
twenty years the difference is not small. Each pot compounds on its own and
they are only ever added together for display.

**They stay off the chart.** Six lines would need a palette that keeps six
series apart for a colourblind reader and would smear on a phone-width plot, so
the chart keeps one **Investments** line for all three. The pots behind it are
listed indented beneath that row in the summary — and only once two of them
have anything in them, since a breakdown of one pot says nothing the row above
it did not.

**Only the first portfolio is fed by the import**, and only the first is what
"Less investing" measures against take-home pay. The other two are assumed to
be funded from elsewhere; the calculator does not pretend to know where. That
is the only way the first differs — it is named and renamed like the other two,
and its card is headed by its name like theirs, because the summary lists all
three side by side and one card that would not follow its own row there is the
odd one out.

### The retirement sums

Give an age and a horizon that reaches 55, and the calculator says whether the
projection clears the Basic, Full or Enhanced Retirement Sum.

**The verdict is in the summary at the top**, not only in its own card. That
card is eighth of nine, past four CPF cards, and a reader who never scrolls
that far reads its absence as "nothing to say" rather than "further down" — so
the top line names the highest sum cleared and what is missing from the next.

**The default horizon does not reach 55 for the people this is for.** Twenty
years from 28 ends at 48, and the sums cannot be measured at all. Rather than
showing nothing, both the summary and the card say how many more years are
needed — the field that fixes it sits *below* the message, so leaving the
reader to work it out would be doubly unhelpful.

### CPF LIFE payouts

A balance at 55 is a number. What it pays every month is the thing being bought
with it, so the calculator says both — in the summary at the top and in a card
of its own below the sums.

**The payout is a range, because CPF publishes one.** Two members setting aside
the same amount do not receive the same monthly payout, and the single figure
most write-ups carry is the top of that range. Quoting only that would flatter
every projection here.

**The line is CPF's arithmetic, not a curve fitted to it.** It is calibrated on
two published points for the 2026 cohort — $110,200 paying $860–$950 a month,
$220,400 paying $1,670–$1,780 — and it then reproduces the published Enhanced
figure, $3,290–$3,440 on $440,800, to the dollar. That the third point falls
out of a line drawn through the other two is the evidence the relationship is
real, and it is the check that fails first if an anchor is ever mistyped.

**The payout is not proportional to the balance.** CPF's figures work out at
$8.62 a month per $1,000 at the Basic sum and $7.80 at the Enhanced. Scaling one
ratio — the obvious shortcut — would overstate a large balance by about a
hundred dollars a month.

**Payouts start at 65, not 55.** The Retirement Account is formed at 55 and then
sits for ten years earning interest before a cent is paid. CPF's figures are
keyed on the balance at 55 and already contain that decade, so nothing here
compounds it twice.

**Only what reaches the Enhanced sum is annuitised.** Eligible savings above it
stay in the Ordinary and Special Accounts — still yours, simply not buying
payouts. The card names that money rather than letting it vanish from the
arithmetic without explanation.

**Below the CPF LIFE minimum there is no payout to quote.** CPF includes a
member automatically from $60,000 in the Retirement Account at 65, which is
about $40,500 at 55. Under that, the Retirement Sum Scheme pays out until the
savings are gone — not a lifelong income — so the card says so instead of
printing "$0.00 a month", which would read as an answer rather than as a
different scheme on different terms.

**The figure is in the dollars of the year it is paid.** The projection is
nominal throughout and so is this, which matters most for the people it matters
to: someone 28 today is reading a payout in 2063 dollars.

Standard Plan throughout. The Basic Plan pays less and leaves more to bequeath;
the Escalating Plan starts about a fifth lower and rises 2% a year.

Three things make this easy to get wrong, and all three are handled rather than
left to the reader:

- **MediSave is not counted.** The Retirement Account is formed at 55 from the
  Special Account and then the Ordinary Account; MediSave stays where it is.
  Counting it would clear the bar with money that was never eligible, so the
  card shows the excluded amount and says why.
- **The comparison happens at 55**, when the Retirement Account is formed — not
  at the end of a projection that may run well past it. A projection stopping
  before 55 says so rather than showing nothing, because an absent card reads
  as "you are fine".
- **The sums rise with every cohort**, and are fixed for life at the year *you*
  turn 55. Measuring a 2053 balance against the 2026 Full sum would clear it on
  paper and miss it by half in life.

Only the cohorts up to **2027** have been announced — Budget 2022 set 2023 to
2027 rising about 3.5% a year. Anything later is this app's extrapolation, not
CPF's figures, and the card says so in as many words. The base sum and the
assumed rise are both inputs.

Full is twice Basic, which has held throughout. **Enhanced is not a fixed
ratio**: it was three times Basic until the 2025 cohort and four times from it.
That multiple is policy and has already moved once, so it is encoded against
the year it changed rather than assumed — treating it as arithmetic would
quietly misstate every cohort on the other side of the change, and hide that it
can move again.

| Turning 55 in | BRS | FRS | ERS |
|---|---|---|---|
| 2023 | $99,400 | $198,800 | $298,200 |
| 2024 | $102,900 | $205,800 | $308,700 |
| 2025 | $106,500 | $213,000 | $426,000 |
| 2026 | $110,200 | $220,400 | $440,800 |
| 2027 | $114,100 | $228,200 | $456,400 |

A test reproduces the Basic column from the base and the rate, which is what
says the two belong to each other.

**Almost nothing here encodes CPF policy.** The age allocation table above is
the single exception, and only when an age is given. Contribution percentages,
the wage ceiling and the interest rates are all inputs, because every one of
them has changed in recent years and a calculator quietly using a stale figure
is worse than one that asks. Defaults lean conservative where a guess would flatter the
result: CPF interest starts at the Ordinary Account's 2.5% rather than the 4%
paid on Special and MediSave, and there is no pay rise unless you set one.

The **wage ceiling is worth setting even if your salary is under it today**.
Over twenty years a rising salary crosses it, and ignoring that overstates CPF
for every year after. Leave it blank for no ceiling; zero means the same thing,
not a ceiling of nothing.

The result separates **what was paid in from what was earned**, which is the
point of the exercise — a single final number would not say how much of it was
growth.

It is a projection, not a forecast: fixed rates compounded monthly, with
contributions at month end. Inputs are saved on the device, and like everything
else here they are sent nowhere.

## Starting an analysis

Every stock's detail screen has **Run framework analysis**. It copies a prompt
to the clipboard and then opens Claude carrying it, so a deep dive on whatever
you are looking at is one tap rather than a retyped ticker.

The prompt is deliberately bare — `Run the framework on NVDA`. That exact
wording is one the framework lists as a trigger, so a paraphrase risks a plain
answer instead of the structured deep dive. Nothing else is sent: position size
would anchor the analysis to a holding already owned, and the chart's current
technicals answer a question the framework asks for itself.

**Set a project under Settings** and the button opens that project instead of a
new chat, so an analysis starts where the framework and its history already
are. Paste the project's address; a link copied from a chat inside the project
resolves to the project itself, and anything that is not a claude.ai project
link is refused rather than stored — sending the button somewhere arbitrary
would be worse than falling back to a new chat.

**Without a project set, the button asks first.** It used to fall back silently
to a bare chat, which from the phone is indistinguishable from a broken link —
the analysis simply opened somewhere outside the project, with none of the past
ones to refer to. Now it says so and offers to take you to Settings, with
"Open anyway" still there for when a plain chat is what you want.

Claude has no documented way to open a new chat *already inside* a project, so
the button lands on the project and the prompt is pasted from the clipboard.

**The prompt is not attached to a project link**, only to the new-chat one.
`?q=` is the parameter the new-chat route reads; a project page has no composer
for it to fill, and carrying it risks being routed to a bare chat — precisely
the outcome a project link exists to avoid. The clipboard carries the prompt
either way, and always did.

**The clipboard copy happens first, and it is the part that matters.** Whether
a link can carry text into Claude is not something this project can guarantee —
the behaviour has changed before, and the documentation is not reachable from
the environment this was written in. So the button never depends on it: if the
link opens Claude with the prompt filled in, good; if it opens a blank chat, or
nothing is installed to handle it, the prompt is already copied and the message
says to paste it. The handoff works either way.

The project link is stored on the device, never compiled in: it identifies one
person's project and this repository is public.

On Android the manifest declares an `https` intent query. Without it, from
Android 11 on, an app cannot see which other apps handle web links and the
launch silently reports failure.

## Analysis checklist scores

If your sheet carries score columns, each holding shows them under its value:

```
Fin 12/17 · Moat 8/14         scored 3 weeks ago
```

The columns are found the same way as quantity and cost — in the tickers'
header row, matched on the leading word, and never a column another kind has
already claimed. `Financial score`, `Financials`, `Fin score`, `Moat score`,
`Moat` and `Scored` all work.

**The app records these; it does not compute them.** The financial criteria
need multi-year statements and peer benchmarking, and several of the moat
criteria are outright qualitative — whether a brand commands premium pricing is
not something a price feed can answer. The judgement is made elsewhere and the
sheet is where it is written down.

**Each score carries the scale it was marked on, because the scale varies.**
The framework scores financials out of 19, but criteria that do not apply to a
company are dropped rather than scored zero — an ETF has no management to
assess, a young company no long record — so one holding is marked out of 17 and
the next out of 18. Whatever the sheet writes is what is shown. A bare number
with no scale beside it is read against the framework's own, which is the only
thing it can mean.

Nothing is rescaled to a common denominator. 12/17 is not 12/19, and converting
between them would invent a judgement nobody made — so comparing two scores on
different scales is left to the reader, who knows which criteria were dropped.

**A score always carries its age**, because it is a snapshot. One from six
months ago may predate two earnings reports, and a stale judgement shown as
current is the way this feature would mislead. Past six months it is labelled
**stale** — in words and by contrast, never by colour, because red already
means a loss on that row and a stale date in the same red would read as a bad
number rather than an old one.

**Two things are refused rather than guessed:**

- A mark larger than its own scale. A `20/17` is a slip, and displaying it
  would lend a wrong number the authority of a score. So is a scale of zero, or
  one large enough to be a year rather than a checklist. A `-`, the way a sheet
  says "not assessed", leaves the holding with no score rather than a zero —
  which would read as the worst possible judgement.
- An ambiguous date. `2026-08-15` and `15/08/2026` are read; **`03/04/2026` is
  not**, because it is March 4th to half the world and April 3rd to the other
  half. Since this date drives the staleness label, being a month wrong would
  make an old score look current. **Format the column as `YYYY-MM-DD` and it
  always reads.**

A holding scored but undated keeps its scores: the date is what is missing, not
the judgement.

**The age and the date, on two lines.** The row says how old a score is —
`scored 3 weeks ago`, `· stale` past six months — and prints the date itself
underneath, `16 Sep 2026`. They answer different questions: the age says whether
earnings have overtaken the judgement, the date says whether it is the one you
put in the sheet, and neither can be read off the other. Side by side on a
phone-width row they do not both fit, and the half that gets cut is the date —
so it gets a line to itself.

The date is spelled, never all digits. `03/04/2026` is the ambiguity the
importer refuses to read, and printing dates back in the form it refuses would
be a strange thing for this app to do.

**Which kind of missing, said in words.** A score with no date carries one of
three messages, because they are fixed in three different places:

| The row says | What it means | Where to fix it |
| --- | --- | --- |
| `no date column` | The sheet has no column naming when scores were arrived at | The sheet's columns — or a **published CSV frozen before you added one** |
| `no date` | The column is there; this row's cell is empty | That row |
| `date unreadable` | The cell held something that could not be read | That cell's format |

The first two wore the same words once, and they are the two most easily
confused: a reader told `no date` goes to reformat a cell that is not the
problem, when the column never reached the app at all. That last case is worth
knowing about — the app reads the **Publish to web** CSV, which is a separate
snapshot from the live sheet. If "Automatically republish when changes are
made" is unticked, a column added after the last manual publish never appears,
and every row reads `no date column` however correct the sheet looks.

Accepted headings, case and punctuation ignored: `Scored`, `Score date`,
`Date scored`, `Reviewed`, or anything starting `Scored…`, `Analysed…`,
`Analyzed…` or `Reviewed…`. A column headed only `Date` is deliberately not
matched — sheets carry `Date bought` and `Date added` too, and latching the
staleness label onto a purchase date would report nonsense confidently.

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

Debug and profile builds need no setup. A release build signs with a stand-in
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

### The one committed key

`android/ci-signing/ci.keystore` is checked in, and its password sits in
`android/app/build.gradle.kts` in plain sight. That is deliberate. It is not
the app's key and it never signs `io.github.lepenguin22.ticker` — only the
`.ci` build described under Continuous integration.

It exists because the obvious stand-in, Android's debug key, is generated per
machine. Every CI run is a fresh container, so every build came out signed by a
different certificate, and a phone will not install a build over one signed by
a different key. The symptom was a bare "App not installed" on an APK that had
built cleanly, with nothing in the build log to explain it. A committed key
makes consecutive CI builds upgrades of each other.

The cost of publishing it is that anyone can build an APK claiming the `.ci`
identity, so treat a `.ci` build like any other sideloaded file: install one
only if it came from this repository's own CI run. To remove even that, move
the keystore into an Actions secret and have the workflow write it out before
building; nothing else needs to change.

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
  holding.dart           A holding, its size, cost and scores; totals
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
lib/screens/             Watchlist, Search, Detail, Alerts, Import, Settings,
                         Calculator
lib/widgets/             QuoteRow, PriceChart, RsiPane, Sparkline, ChangePill,
                         AlertSheet, PortfolioSummary
lib/utils/
  format.dart            Price, change and date formatting
  chart.dart             Line and candle geometry, zoom limits (unit tested)
  projection.dart        Compound growth of savings and CPF (unit tested)
  indicators.dart        Moving averages, Wilder RSI, crossings (unit tested)
  portfolio_csv.dart     Holdings, counts, costs and scores from CSV (tested)
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

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and every push to `main`:

| Job | What it does |
| --- | --- |
| **Analyze and test** | `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos --fatal-warnings`, `flutter test` |
| **Build APK** | `flutter build apk --release`, uploaded as a downloadable artifact |

Formatting is a failure rather than a silent reformat, and analyzer infos are
fatal alongside warnings — the project is clean today, and letting one through
is how a codebase stops being clean.

**The APK job is the point of this.** The test suite says the code is correct;
only Gradle says the app still assembles. It is a release build because that is
where builds actually break — minification and icon tree shaking do not run in
debug — and the result is installable for testing on a device.

**That artifact is not a store build.** `android/app/build.gradle.kts` falls
back to the committed CI key when `android/key.properties` is absent, which is
why this needs no secrets, and equally why the APK it produces must not be
distributed — that key is public. A real signed build still comes from a
machine that has the keystore.

The job then checks its own output: it reads the finished APK and fails if the
package id is not the `.ci` variant, or if the signing certificate is not the
committed one. Both are invisible in the build log, and both, when wrong,
reach you only as an unexplained "App not installed".

**It also installs as a separate app.** A release build without the keystore
gets the application id `io.github.lepenguin22.ticker.ci` and the label
**Portfolio Alerts CI**. Android refuses to replace an app signed with one key
by a build signed with another, so without this a CI APK simply fails to
install over the real app — the only remedy being to uninstall it and lose its
data. As a separate id the two sit side by side, and the label keeps them
apart on the home screen, since they share an icon.

Being a separate app, it has **its own storage**: an empty watchlist, and no
portfolio until the sheet is imported into it. That is the trade for not
touching the real app. Only builds that find the keystore keep the plain
`io.github.lepenguin22.ticker` id, so nothing about a proper signed release
changes.

The Flutter version is pinned so an upstream release cannot turn CI red on its
own; bump it deliberately, with the suite run against the new version.

## Ideas for later

- Server-side alert checking, so notifications are punctual rather than
  best-effort — the single biggest limitation of the current design
- Volume bars under the price, from data the chart payload already carries
- Portfolio weight per holding, now that values are known
- Drag-to-reorder in place of the long-press sheet
- A home screen widget
