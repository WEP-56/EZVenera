import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/json_file_store.dart';

class PluginDataStore {
  PluginDataStore(this.rootPath);

  final String rootPath;

  /// One store per source key: the write queue lives on the store instance,
  /// so concurrent writes to the same source are serialized and atomic
  /// instead of racing a bare writeAsString (F-01).
  final Map<String, JsonFileStore> _stores = {};

  Future<void> ensureInitialized() async {
    await Directory(rootPath).create(recursive: true);
  }

  JsonFileStore _storeFor(String sourceKey) {
    return _stores.putIfAbsent(
      sourceKey,
      () => JsonFileStore(File(_filePath(sourceKey))),
    );
  }

  Future<Map<String, dynamic>> read(String sourceKey) async {
    await ensureInitialized();
    return _storeFor(sourceKey).read();
  }

  Future<void> write(String sourceKey, Map<String, dynamic> value) async {
    await ensureInitialized();
    await _storeFor(sourceKey).write(value);
  }

  Future<void> delete(String sourceKey) async {
    final file = File(_filePath(sourceKey));
    if (await file.exists()) {
      await file.delete();
    }
    // Drop the cached store (and its write queue) so a deleted source leaves
    // nothing behind; reinstalling the same key creates a fresh store.
    _stores.remove(sourceKey);
  }

  String _filePath(String sourceKey) => p.join(rootPath, '$sourceKey.json');
}
