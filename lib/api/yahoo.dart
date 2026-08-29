import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/types.dart';
import 'parse.dart';

/// Thin client over Yahoo Finance's public chart/search endpoints.
///
/// These endpoints need no API key, but they are undocumented: they rate
/// limit, they occasionally return HTML error pages, and one host can be
/// unhealthy while the other is fine. Every request therefore falls back from
/// query1 to query2 and is bounded by a timeout.

/// A network/HTTP level failure, as opposed to a malformed payload
/// ([FeedException]).
class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cooperative cancellation for requests whose result is no longer wanted —
/// a superseded search, or a screen that has been popped.
///
/// Dart futures cannot be aborted mid-flight, so this does not tear down the
/// socket. It stops work that has not started yet (the remaining symbols of a
/// fan-out, the fallback host) and marks the result as unwanted so callers
/// discard it rather than writing it into a disposed widget.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Thrown internally when a token is cancelled part-way through a request.
class _CancelledException implements Exception {
  const _CancelledException();
}

const _hosts = [
  'https://query1.finance.yahoo.com',
  'https://query2.finance.yahoo.com',
];

const _requestTimeout = Duration(seconds: 12);

const _unreachable = 'Could not reach Yahoo Finance. Check your connection.';

/// Yahoo returns 429 to clients that look automated, so present a browser UA.
const _headers = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept': 'application/json',
};

class YahooApi {
  YahooApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Future<Object?> _fetchJsonFrom(String url) async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const NetworkException('Request timed out.');
    } on http.ClientException {
      // The IO client wraps socket-level failures (no route, DNS, connection
      // reset) in this, and their messages are not worth showing a user.
      throw const NetworkException(_unreachable);
    }

    if (res.statusCode != 200) {
      throw NetworkException(
        res.statusCode == 429
            ? 'Rate limited by Yahoo Finance. Wait a moment and try again.'
            : 'Request failed (HTTP ${res.statusCode})',
      );
    }

    try {
      return jsonDecode(res.body);
    } on FormatException {
      // Yahoo serves an HTML error page rather than JSON when it is unhappy.
      throw const NetworkException('Unexpected response from Yahoo Finance.');
    }
  }

  /// Issues [path] against each host in turn, returning the first JSON body.
  Future<Object?> _fetchJson(String path, CancelToken? token) async {
    Object? lastError;
    for (final host in _hosts) {
      if (token?.isCancelled ?? false) throw const _CancelledException();
      try {
        return await _fetchJsonFrom(host + path);
      } on NetworkException catch (err) {
        lastError = err;
      }
    }
    if (lastError is NetworkException) throw lastError;
    throw const NetworkException(_unreachable);
  }

  String _chartPath(String symbol, String range, String interval) =>
      '/v8/finance/chart/${Uri.encodeComponent(symbol)}'
      '?range=$range&interval=$interval&includePrePost=false';

  /// Fetches the current quote plus an intraday series for the sparkline.
  Future<Quote> fetchQuote(String symbol, {CancelToken? token}) async {
    final payload = await _fetchJson(_chartPath(symbol, '1d', '5m'), token);
    return parseQuote(payload);
  }

  /// Fetches quotes for many symbols at once.
  ///
  /// Yahoo's batch quote endpoint now requires a session crumb, so this fans
  /// out one chart request per symbol instead. Failures are returned
  /// per-symbol rather than failing the batch: one delisted ticker should not
  /// blank the whole watchlist.
  Future<QuoteBatch> fetchQuotes(
    List<String> symbols, {
    CancelToken? token,
  }) async {
    final quotes = <Quote>[];
    final errors = <String, String>{};

    final settled = await Future.wait(
      symbols.map((symbol) async {
        try {
          return _Settled.value(await fetchQuote(symbol, token: token));
        } catch (err) {
          return _Settled.error(symbol, err);
        }
      }),
    );

    for (final outcome in settled) {
      final quote = outcome.quote;
      if (quote != null) {
        quotes.add(quote);
      } else if (outcome.error is! _CancelledException) {
        errors[outcome.symbol!] = describeError(outcome.error);
      }
    }
    return QuoteBatch(quotes: quotes, errors: errors);
  }

  /// Fetches a price series for the detail screen.
  Future<History> fetchHistory(
    String symbol,
    RangeKey range, {
    CancelToken? token,
  }) async {
    final payload = await _fetchJson(
      _chartPath(symbol, range.range, range.interval),
      token,
    );
    return parseHistory(payload, range);
  }

  /// Looks up symbols by company name or ticker.
  Future<List<SearchResult>> searchSymbols(
    String query, {
    CancelToken? token,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final payload = await _fetchJson(
      '/v1/finance/search?q=${Uri.encodeComponent(q)}'
      '&quotesCount=20&newsCount=0&listsCount=0',
      token,
    );
    return parseSearch(payload);
  }
}

/// The outcome of a fan-out refresh: the quotes that came back, and a message
/// for each symbol that did not.
class QuoteBatch {
  const QuoteBatch({required this.quotes, required this.errors});

  final List<Quote> quotes;
  final Map<String, String> errors;
}

class _Settled {
  const _Settled.value(this.quote) : symbol = null, error = null;
  const _Settled.error(this.symbol, this.error) : quote = null;

  final Quote? quote;
  final String? symbol;
  final Object? error;
}

/// Turns any thrown value into something worth showing a user.
String describeError(Object? err) {
  if (err is NetworkException) return err.message;
  if (err is FeedException) return err.message;
  if (err is TimeoutException) return 'Request timed out.';
  if (err is Exception) return err.toString();
  return 'Something went wrong.';
}
