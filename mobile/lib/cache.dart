import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// A small, best-effort snapshot, isolated by backend and profile.
class TrackerCache {
  final String key;
  Future<void> _writes = Future.value();
  TrackerCache(AppConfig config)
    : key = 'tracker_snapshot_v1:${config.apiBase}:${config.userId}';

  Future<Map<String, dynamic>?> load() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(key);
      if (text == null) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      return data['version'] == 1 ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> store(Map<String, dynamic> snapshot) {
    // Encode before scheduling so later controller changes cannot alter this write.
    final text = jsonEncode(snapshot);
    _writes = _writes.then((_) async {
      try {
        await (await SharedPreferences.getInstance()).setString(key, text);
      } catch (_) {
        // A cache failure must never fail a confirmed expense or network refresh.
      }
    });
    return _writes;
  }
}
