import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';

const _alertsKey = 'ticker.alerts.v1';

/// Persistence for price alerts.
///
/// Read and written from two isolates: the UI, and the background worker that
/// fires alerts. `SharedPreferences` reads through to the platform store each
/// time an instance is created, so the worker sees alerts added since it was
/// scheduled — but the two can still interleave, which is why the worker
/// re-reads immediately before it writes rather than holding a list across an
/// await.
class AlertStorage {
  Future<List<PriceAlert>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Discards anything the platform cached in this isolate, so a worker
      // started before the user's latest edit still sees it.
      await prefs.reload();
      final raw = prefs.getString(_alertsKey);
      if (raw == null) return [];
      final parsed = jsonDecode(raw);
      if (parsed is! List) return [];

      final out = <PriceAlert>[];
      for (final entry in parsed) {
        if (entry is! Map) continue;
        try {
          out.add(PriceAlert.fromJson(entry.cast<String, dynamic>()));
        } catch (_) {
          // Drop one unreadable alert rather than the whole list: the stored
          // shape may predate a change to PriceAlert.
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<PriceAlert> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _alertsKey,
        jsonEncode(alerts.map((a) => a.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Ignore: the in-memory list is still correct for this session.
    }
  }
}
