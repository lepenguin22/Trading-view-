import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/valuation.dart';
import 'yahoo.dart' show NetworkException;

/// Fetches a discounted-cash-flow fair value from Financial Modeling Prep.
///
/// FMP is used because it publishes a DCF directly rather than leaving the
/// model to be assembled from cash-flow statements. The number is FMP's own
/// output — a different provider's DCF for the same company will differ, often
/// materially, which is why the UI attributes it.
class ValuationSource {
  ValuationSource({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://financialmodelingprep.com';

  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 15);

  void dispose() => _client.close();

  /// Reads the DCF for [symbol]. Throws [NetworkException] with a message fit
  /// to show the user.
  Future<Valuation> fetch(String symbol, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw const NetworkException(
        'No API key set. Add a Financial Modeling Prep key in Settings.',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/api/v3/discounted-cash-flow/${Uri.encodeComponent(symbol)}'
      '?apikey=${Uri.encodeComponent(apiKey.trim())}',
    );

    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const NetworkException('The valuation request timed out.');
    } on http.ClientException {
      throw const NetworkException(
        'Could not reach the valuation provider. Check your connection.',
      );
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const NetworkException(
        'That API key was rejected. Check it in Settings.',
      );
    }
    if (res.statusCode == 429) {
      throw const NetworkException(
        'Valuation rate limit reached. The free plan allows a few hundred '
        'requests a day; try again tomorrow.',
      );
    }
    if (res.statusCode != 200) {
      throw NetworkException(
        'Valuation request failed (HTTP ${res.statusCode}).',
      );
    }

    return parseValuation(res.body, symbol);
  }
}

/// Parses an FMP DCF response.
///
/// Written to accept more than one shape on purpose: FMP's legacy endpoint
/// returns `dcf`, its newer one returns `equityValuePerShare`, and this could
/// not be verified against the live service from the build environment. Any
/// of the known keys is accepted, and anything unusable is reported rather
/// than defaulted.
Valuation parseValuation(String body, String symbol) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const NetworkException(
      'The valuation provider returned something that is not JSON.',
    );
  }

  // The endpoint answers with a single-element list; an unknown symbol gives
  // an empty one rather than a 404.
  final Map<String, dynamic>? row;
  if (decoded is List) {
    row = decoded.isEmpty ? null : _asMap(decoded.first);
  } else {
    row = _asMap(decoded);
  }

  if (row == null) {
    throw NetworkException('No valuation published for $symbol.');
  }

  // A provider error often arrives as 200 with a message body.
  final message = row['Error Message'] ?? row['error'] ?? row['message'];
  if (message is String && message.isNotEmpty) {
    throw NetworkException(message);
  }

  final dcf = _firstNumber(row, const [
    'dcf',
    'equityValuePerShare',
    'DCF',
    'discountedCashFlow',
  ]);
  if (dcf == null) {
    throw NetworkException('No valuation published for $symbol.');
  }
  if (dcf <= 0) {
    // Real for a company with negative projected cash flows. Surfaced rather
    // than shown, because every ratio built on it would be meaningless.
    throw NetworkException(
      'The published valuation for $symbol is not a usable figure.',
    );
  }

  return Valuation(
    symbol: (row['symbol'] as String?) ?? symbol,
    dcf: dcf,
    currency: (row['currency'] as String?) ?? 'USD',
    fetchedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

double? _firstNumber(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is num && value.isFinite) return value.toDouble();
    // Some providers quote numbers as strings.
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
  }
  return null;
}
