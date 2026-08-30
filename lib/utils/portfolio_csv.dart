import 'package:csv/csv.dart';

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
const _maxScanRows = 5000;

/// Extracts the tickers from the first holdings table in [csv].
///
/// Returns them uppercased, in sheet order, without duplicates. An empty list
/// means no ticker column was found — the caller should say so rather than
/// silently importing nothing.
List<String> parseHoldingsCsv(String csv) {
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

  final seen = <String>{};
  final out = <String>[];

  for (var r = header.row + 1; r < rows.length && r < _maxScanRows; r++) {
    final cell = _cell(rows[r], header.column);

    // A blank ticker cell ends the table. This is what keeps the closed
    // positions below it out of the import.
    if (cell.isEmpty) break;

    final symbol = normaliseTicker(cell);
    if (symbol == null) continue;
    if (seen.add(symbol)) out.add(symbol);
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
