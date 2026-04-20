import 'package:flutter/foundation.dart';

import 'history_models.dart';
import 'json_store.dart';

class HistoryController extends ChangeNotifier {
  HistoryController._();

  static final HistoryController instance = HistoryController._();

  final JsonStore _store = JsonStore('history.json');
  List<ReadingHistoryEntry> _entries = const <ReadingHistoryEntry>[];
  bool _initialized = false;

  List<ReadingHistoryEntry> get entries =>
      List<ReadingHistoryEntry>.unmodifiable(_entries);

  ReadingHistoryEntry? find(String sourceKey, String comicId) {
    for (final entry in _entries) {
      if (entry.sourceKey == sourceKey && entry.comicId == comicId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final raw = await _store.readList();
    _entries = raw.map(ReadingHistoryEntry.fromJson).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _initialized = true;
    notifyListeners();
  }

  Future<void> record(ReadingHistoryEntry entry) async {
    await initialize();
    _entries = [entry, ..._entries.where((item) => item.key != entry.key)];
    await _persist();
    notifyListeners();
  }

  Future<void> remove(ReadingHistoryEntry entry) async {
    await initialize();
    _entries = _entries.where((item) => item.key != entry.key).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() {
    return _store.writeList(_entries.map((entry) => entry.toJson()).toList());
  }
}
