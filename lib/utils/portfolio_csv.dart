import 'package:csv/csv.dart';

import '../models/holding.dart';
import '../models/score.dart';

/// Reads the holdings table out of a spreadsheet exported as CSV.
///
/// Written against a real portfolio sheet, whose shape is the awkward part: the
/// table does not start at row 1 or column A, there is a note row above the
/// header, and further down the *same* tab sits a second table of closed
/// positions with its own ticker column. Importing that second table would put
/// stocks the user has already sold onto their watchlist, so the parser takes
/// the first table only and stops at its end.

/// Header names that mark the ticker column.
const _tickerHeaders = {'ticker', 'symbol', 'tickers', 'symbols'};

/// Deliberately excludes 'stock' and 'name': the closed-positions table below
/// the holdings is headed "Stock", and matching it is exactly the mistake this
/// parser exists to avoid.
/// Header names that mark the share-count column exactly.
///
/// Only ever looked for in the same header row as the ticker column, so a
/// quantity belonging to the closed-positions table below cannot be picked up
/// by mistake.
const _sharesHeaders = {'no of shares', 'number of shares', 'amount held'};

/// First words that mark a share-count column however it continues.
///
/// Real sheets write "Shares bought", "Shares held", "Quantity owned". Matching
/// on the leading word catches those, while still refusing a header that merely
/// mentions shares later on — "Value of shares" and "Principal invested" are
/// money columns, and reading one as a quantity would multiply a value by a
/// price.
const _sharesLeadingWords = {
  'shares',
  'share',
  'quantity',
  'qty',
  'units',
  'unit',
  'holding',
  'holdings',
};

/// Header names that mark the average-cost column exactly.
const _costHeaders = {'cost', 'cost basis', 'book cost', 'price paid', 'paid'};

/// First words that mark an average-cost column however it continues.
///
/// "Average price bought", "Avg cost", "Buy price", "Purchase price". This is
/// a price *per share*, which is why a total-cost column must not be matched:
/// "Principal invested" is the whole position, and reading it as a unit price
/// would overstate the cost by a factor of the share count. Nor is the live
/// price a cost — "Current stock price" leads with a word not listed here.
const _costLeadingWords = {
  'average',
  'avg',
  'cost',
  'buy',
  'bought',
  'purchase',
  'entry',
};

/// Header names that mark the financial-score column.
///
/// The score comes from the analysis framework, which the app cannot run: the
/// 19 criteria need multi-year statements and peer benchmarking, and no price
/// feed carries those. The sheet is where a judgement already made gets
/// recorded, so the app reads it rather than pretending to compute it.
const _financialScoreHeaders = {'financial score', 'fin score', 'financials'};
const _financialScoreLeadingWords = {'financial', 'fundamentals'};

/// Header names that mark the moat-score column.
const _moatScoreHeaders = {'moat score', 'moat'};
const _moatScoreLeadingWords = {'moat', 'economic'};

/// Header names that mark the date the scores were arrived at.
const _scoredHeaders = {'scored', 'score date', 'date scored', 'reviewed'};
const _scoredLeadingWords = {'scored', 'analysed', 'analyzed', 'reviewed'};

/// The scales the framework scores on, used only when a cell gives a bare
/// number and the sheet has not said what it was out of.
///
/// Not a rule the sheet must obey. Criteria that do not apply to a company are
/// dropped from its checklist rather than scored zero, so the denominator
/// genuinely varies — 12/17 beside 15/18 — and whatever the sheet writes is
/// what the app carries.
const financialScoreMax = 19;
const moatScoreMax = 14;

const _maxScanRows = 5000;

/// Extracts the holdings from the first table in [csv].
///
/// Returns them uppercased, in sheet order, without duplicates. Share counts
/// come from a quantity column in the same header row when there is one, and
/// are left null when there is not — a sheet listing only tickers is still a
/// portfolio, just one without values.
///
/// An empty list means no ticker column was found — the caller should say so
/// rather than silently importing nothing.
List<Holding> parseHoldingsCsv(String csv) {
  if (csv.trim().isEmpty) return const [];

  final List<List<dynamic>> rows;
  try {
    rows = const CsvDecoder(
      // Blank lines must survive: the empty row after the last holding is what
      // marks the end of the table, and skipping it would run the parser
      // straight into the closed-positions table below.
      skipEmptyLines: false,
      // Everything is read as text; a ticker is never a number, and letting
      // the decoder coerce cells would turn a share count into a double for
      // no benefit.
      dynamicTyping: false,
    ).convert(csv);
  } catch (_) {
    return const [];
  }

  final header = _findTickerColumn(rows);
  if (header == null) return const [];

  final headerRow = rows[header.row];
  final sharesColumn = _findColumn(
    headerRow,
    exact: _sharesHeaders,
    leading: _sharesLeadingWords,
    skip: {header.column},
  );
  final costColumn = _findColumn(
    headerRow,
    exact: _costHeaders,
    leading: _costLeadingWords,
    // A column can only mean one thing: whichever kind claimed it first keeps
    // it, so a quantity is never also read as a price.
    skip: {header.column, ?sharesColumn},
  );
  final claimed = {header.column, ?sharesColumn, ?costColumn};

  final financialScoreColumn = _findColumn(
    headerRow,
    exact: _financialScoreHeaders,
    leading: _financialScoreLeadingWords,
    skip: claimed,
  );
  if (financialScoreColumn != null) claimed.add(financialScoreColumn);

  final moatScoreColumn = _findColumn(
    headerRow,
    exact: _moatScoreHeaders,
    leading: _moatScoreLeadingWords,
    skip: claimed,
  );
  if (moatScoreColumn != null) claimed.add(moatScoreColumn);

  final scoredAtColumn = _findColumn(
    headerRow,
    exact: _scoredHeaders,
    leading: _scoredLeadingWords,
    skip: claimed,
  );

  final seen = <String>{};
  final out = <Holding>[];

  for (var r = header.row + 1; r < rows.length && r < _maxScanRows; r++) {
    final cell = _cell(rows[r], header.column);

    // A blank ticker cell ends the table. This is what keeps the closed
    // positions below it out of the import.
    if (cell.isEmpty) break;

    final symbol = normaliseTicker(cell);
    if (symbol == null) continue;
    if (!seen.add(symbol)) continue;

    out.add(
      Holding(
        symbol: symbol,
        shares: sharesColumn == null
            ? null
            : parseShares(_cell(rows[r], sharesColumn)),
        costPerShare: costColumn == null
            ? null
            : parseMoney(_cell(rows[r], costColumn)),
        financialScore: financialScoreColumn == null
            ? null
            : parseScore(
                _cell(rows[r], financialScoreColumn),
                financialScoreMax,
              ),
        moatScore: moatScoreColumn == null
            ? null
            : parseScore(_cell(rows[r], moatScoreColumn), moatScoreMax),
        scoredAt: scoredAtColumn == null
            ? null
            : parseSheetDate(_cell(rows[r], scoredAtColumn)),
      ),
    );
  }

  return out;
}

/// Locates the ticker column by its header.
({int row, int column})? _findTickerColumn(List<List<dynamic>> rows) {
  for (var r = 0; r < rows.length && r < _maxScanRows; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final value = _cell(rows[r], c).toLowerCase();
      if (_tickerHeaders.contains(value)) return (row: r, column: c);
    }
  }
  return null;
}

/// Locates a column in the header row the tickers were found on.
///
/// Matches an [exact] header name, or one whose first word is in [leading].
/// Columns in [skip] are already claimed by another kind, so a single column
/// is never read as two different things.
int? _findColumn(
  List<dynamic> headerRow, {
  required Set<String> exact,
  required Set<String> leading,
  required Set<int> skip,
}) {
  for (var c = 0; c < headerRow.length; c++) {
    if (skip.contains(c)) continue;
    final value = _normaliseHeader(_cell(headerRow, c));
    if (value.isEmpty) continue;
    if (exact.contains(value)) return c;
    if (leading.contains(value.split(' ').first)) return c;
  }
  return null;
}

/// Lower-cases a header and reduces its punctuation and runs of spaces to
/// single spaces, so "No. of Shares" and "no of shares" are the same header.
String _normaliseHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Reads a share count out of a spreadsheet cell.
///
/// Hand-maintained sheets write quantities with thousands separators, stray
/// spaces, and sometimes a trailing unit. Anything that does not resolve to a
/// finite number is null — an unreadable quantity must not become a zero, or a
/// real position would silently value at nothing.
/// Reads a checklist score out of a cell, as a whole number within [max].
///
/// Accepts a bare "14" and a written "14/19" — a sheet maintained by hand will
/// have both. Anything outside 0..[max] is refused: a 25 against a scale of 19
/// is a slip, and showing it would lend a wrong number the authority of a
/// score.
Score? parseScore(String raw, int defaultOutOf) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // "14 / 19" — the sheet states its own scale, and it is taken as written.
  // The framework scores financials out of 19, but not every criterion
  // applies to every company, so a real sheet holds 12/17 beside 15/18.
  // Insisting on one denominator made every such cell unreadable.
  final fraction = RegExp(r'^(-?\d+)\s*/\s*(-?\d+)$').firstMatch(text);
  if (fraction != null) {
    final value = int.tryParse(fraction.group(1)!);
    final outOf = int.tryParse(fraction.group(2)!);
    if (value == null || outOf == null) return null;
    return Score.of(value, outOf);
  }

  // A bare number is read against the framework's own scale, which is the
  // only thing it can mean when the sheet does not say.
  final value = int.tryParse(text);
  return value == null ? null : Score.of(value, defaultOutOf);
}

/// Reads the date a score was arrived at.
///
/// ISO (2026-08-15) is read directly. A slashed or dotted date is read only
/// when the order is unambiguous — one component above 12 can only be the day.
/// A date like 03/04/2026 is deliberately refused: it is March 4th to half the
/// world and April 3rd to the other half, and this date drives a staleness
/// indicator, where being a month wrong would make an old score look current.
/// The app says the date could not be read so the sheet can be corrected.
DateTime? parseSheetDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
  if (iso != null) {
    return _dateFrom(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }

  final parts = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$')
      .firstMatch(text);
  if (parts == null) return null;

  final first = int.parse(parts.group(1)!);
  final second = int.parse(parts.group(2)!);
  final year = int.parse(parts.group(3)!);

  if (first > 12 && second <= 12) return _dateFrom(year, second, first);
  if (second > 12 && first <= 12) return _dateFrom(year, first, second);
  // Both plausible as a month: ambiguous, so unreadable.
  return null;
}

/// Builds a date, rejecting one the calendar rolled over (31 February).
DateTime? _dateFrom(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Reads a money amount out of a spreadsheet cell.
///
/// Same tolerance as [parseShares], plus the currency marks a sheet writes
/// prices with. Anything that does not resolve to a positive number is null: a
/// cost of zero would report the whole position as pure profit.
double? parseMoney(String raw) {
  final value = parseShares(raw.replaceAll(RegExp(r'[^0-9.,()\s-]'), ''));
  if (value == null || value <= 0) return null;
  return value;
}

double? parseShares(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;

  // Accounting notation for a negative: (100) means -100.
  final negated = text.startsWith('(') && text.endsWith(')');
  if (negated) text = text.substring(1, text.length - 1);

  text = text.replaceAll(RegExp(r'[,\s]'), '');
  if (text.isEmpty) return null;

  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return negated ? -value : value;
}

String _cell(List<dynamic> row, int column) {
  if (column >= row.length) return '';
  return (row[column]?.toString() ?? '').trim();
}

/// Normalises a spreadsheet cell into a ticker, or null when it is not one.
///
/// Sheets are hand-maintained: a ticker may be lower case, carry an exchange
/// suffix, or the cell may hold a total or a stray note. Anything that is not
/// plausibly a symbol is dropped rather than sent to the price feed.
String? normaliseTicker(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final upper = trimmed.toUpperCase();

  // Yahoo symbols are letters and digits with . - ^ = separators, e.g. VOD.L,
  // BRK-B, ^FTSE, BTC-USD. Anything with a space or a currency mark is prose
  // or a number, not a symbol.
  if (!RegExp(r'^[\^]?[A-Z0-9]+([.\-=][A-Z0-9]+)*$').hasMatch(upper)) {
    return null;
  }
  // A cell of digits is a row number or a quantity, never a ticker.
  if (RegExp(r'^[0-9]+$').hasMatch(upper)) return null;
  if (upper.length > 15) return null;

  return upper;
}
