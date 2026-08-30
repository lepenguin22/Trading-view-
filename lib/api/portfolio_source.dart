import 'dart:async';

import 'package:http/http.dart' as http;

import '../utils/portfolio_csv.dart';
import 'yahoo.dart' show NetworkException;

/// Fetches a spreadsheet published as CSV.
///
/// Deliberately dumb: it takes a URL the user supplies and reads it as text.
/// No account is linked and no token is stored, which is why this works with a
/// Google Sheet published to the web, an S3 file, or anything else that serves
/// CSV over HTTPS.
class PortfolioSource {
  PortfolioSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  /// Refuses a response larger than this. A holdings sheet is a few kilobytes;
  /// anything approaching a megabyte is the wrong URL, and parsing it would
  /// just stall the UI.
  static const maxBytes = 2 * 1024 * 1024;

  void dispose() => _client.close();

  /// Reads [url] and returns the tickers in its holdings table.
  ///
  /// Throws [NetworkException] with a message fit to show the user.
  Future<List<String>> fetchSymbols(String url) async {
    final uri = parseSheetUrl(url);
    if (uri == null) {
      throw const NetworkException(
        'That does not look like a link. Paste the published CSV URL.',
      );
    }

    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const NetworkException('The sheet took too long to load.');
    } on http.ClientException {
      throw const NetworkException(
        'Could not reach that link. Check your connection and the URL.',
      );
    }

    if (res.statusCode == 404) {
      throw const NetworkException(
        'Nothing at that link. Check the sheet is still published to the web.',
      );
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const NetworkException(
        'That sheet is private. Use File → Share → Publish to web, and '
        'publish the holdings tab as CSV.',
      );
    }
    if (res.statusCode != 200) {
      throw NetworkException('The sheet returned HTTP ${res.statusCode}.');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw const NetworkException(
        'That file is too large to be a holdings sheet.',
      );
    }

    final body = res.body;
    // A private or unpublished Sheets link answers 200 with a sign-in page, so
    // the status code alone is not enough to know this is a spreadsheet.
    if (body.trimLeft().toLowerCase().startsWith('<!doctype html') ||
        body.trimLeft().toLowerCase().startsWith('<html')) {
      throw const NetworkException(
        'That link returned a web page, not CSV. In Sheets use '
        'File → Share → Publish to web and choose CSV.',
      );
    }

    final symbols = parseHoldingsCsv(body);
    if (symbols.isEmpty) {
      throw const NetworkException(
        'No ticker column found. The sheet needs a column headed '
        '"Ticker" or "Symbol".',
      );
    }
    return symbols;
  }
}

/// Validates and normalises a user-supplied sheet URL.
///
/// Returns null when it is not a usable http(s) URL. A Google "publish to web"
/// link is passed through unchanged — it already points at CSV, and rewriting
/// user-supplied URLs is how you end up fetching something they did not mean.
Uri? parseSheetUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
