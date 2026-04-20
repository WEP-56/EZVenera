import 'package:flutter/foundation.dart';

import 'favorite_models.dart';
import 'json_store.dart';

class FavoriteController extends ChangeNotifier {
  FavoriteController._();

  static final FavoriteController instance = FavoriteController._();

  final JsonStore _store = JsonStore('favorites.json');
  List<LocalFavoriteEntry> _entries = const <LocalFavoriteEntry>[];
  bool _initialized = false;

  List<LocalFavoriteEntry> get entries =>
      List<LocalFavoriteEntry>.unmodifiable(_entries);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final raw = await _store.readList();
    _entries = raw.map(LocalFavoriteEntry.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _initialized = true;
    notifyListeners();
  }

  bool contains(String sourceKey, String comicId) {
    return _entries.any(
      (entry) => entry.sourceKey == sourceKey && entry.comicId == comicId,
    );
  }

  Future<void> toggle(LocalFavoriteEntry entry) async {
    await initialize();
    if (contains(entry.sourceKey, entry.comicId)) {
      _entries = _entries
          .where(
            (item) =>
                !(item.sourceKey == entry.sourceKey &&
                    item.comicId == entry.comicId),
          )
          .toList();
    } else {
      _entries = [entry, ..._entries];
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(LocalFavoriteEntry entry) async {
    await initialize();
    _entries = _entries
        .where(
          (item) =>
              !(item.sourceKey == entry.sourceKey &&
                  item.comicId == entry.comicId),
        )
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() {
    return _store.writeList(_entries.map((entry) => entry.toJson()).toList());
  }
}
