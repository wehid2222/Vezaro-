import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';

class DownloadHistoryStore {
  static const String _key = 'download_history_v2';

  Future<List<DownloadItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <DownloadItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <DownloadItem>[];
      return decoded
          .whereType<Map>()
          .map((entry) => DownloadItem.fromJson(Map<String, dynamic>.from(entry)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on FormatException {
      return <DownloadItem>[];
    } on TypeError {
      return <DownloadItem>[];
    }
  }

  Future<void> save(List<DownloadItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(items.map((item) => item.toJson()).toList());
    final ok = await prefs.setString(_key, payload);
    if (!ok) throw StateError('Could not persist download history');
  }
}
