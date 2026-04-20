import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PluginDataStore {
  PluginDataStore(this.rootPath);

  final String rootPath;

  Future<void> ensureInitialized() async {
    await Directory(rootPath).create(recursive: true);
  }

  Future<Map<String, dynamic>> read(String sourceKey) async {
    final file = File(_filePath(sourceKey));
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  Future<void> write(String sourceKey, Map<String, dynamic> value) async {
    final file = File(_filePath(sourceKey));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  Future<void> delete(String sourceKey) async {
    final file = File(_filePath(sourceKey));
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _filePath(String sourceKey) => p.join(rootPath, '$sourceKey.json');
}
