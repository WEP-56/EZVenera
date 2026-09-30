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
    ReadingHistoryEntry? previous;
    for (final item in _entries) {
      if (item.key == entry.key) {
        previous = item;
        break;
      }
    }
    _entries = [
      _accumulate(entry, previous),
      ..._entries.where((item) => item.key != entry.key),
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> remove(ReadingHistoryEntry entry) async {
    await initialize();
    _entries = _entries.where((item) => item.key != entry.key).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> mergeEntries(List<ReadingHistoryEntry> entries) async {
    await initialize();
    final merged = <String, ReadingHistoryEntry>{
      for (final entry in _entries) entry.key: entry,
    };
    for (final entry in entries) {
      final current = merged[entry.key];
      if (current == null) {
        merged[entry.key] = entry;
        continue;
      }
      // Whichever side was opened last wins the bookmark, but both sides'
      // read chapters survive: losing one device must not unread its chapters.
      final newer = entry.timestamp.isAfter(current.timestamp)
          ? entry
          : current;
      final older = identical(newer, entry) ? current : entry;
      merged[entry.key] = _accumulate(newer, older);
    }
    _entries = merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _persist();
    notifyListeners();
  }

  /// A read record only carries the chapter the reader is in, so the chapters
  /// already remembered for the same comic have to be folded in on every write.
  static ReadingHistoryEntry _accumulate(
    ReadingHistoryEntry entry,
    ReadingHistoryEntry? previous,
  ) {
    return entry.copyWith(
      readChapterIds: <String>{
        ...?previous?.readChapterIds,
        if ((previous?.chapterId ?? '').isNotEmpty) previous!.chapterId!,
        ...entry.readChapterIds,
        if ((entry.chapterId ?? '').isNotEmpty) entry.chapterId!,
      },
    );
  }

  Future<void> replaceEntries(List<ReadingHistoryEntry> entries) async {
    await initialize();
    _entries = entries.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() {
    return _store.writeList(_entries.map((entry) => entry.toJson()).toList());
  }
}
