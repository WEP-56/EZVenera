import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/json_file_store.dart';

/// Json-file-backed storage for library lists (favorites, history, folders).
///
/// Delegates to [JsonFileStore] for atomic, serialized, self-healing writes —
/// these files used to be written with a bare `writeAsString`, so a crash
/// mid-write could truncate favorites or history (F-01).
class JsonStore {
  JsonStore(this.fileName);

  final String fileName;
  JsonFileStore? _store;

  Future<void> initialize() async {
    if (_store != null) {
      return;
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'library_state'));
    await root.create(recursive: true);
    _store = JsonFileStore(File(p.join(root.path, fileName)));
  }

  Future<List<Map<String, dynamic>>> readList() async {
    await initialize();
    final decoded = await _store!.readList();
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> writeList(List<Map<String, dynamic>> values) async {
    await initialize();
    await _store!.writeList(values);
  }
}
