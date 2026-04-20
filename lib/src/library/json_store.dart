import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class JsonStore {
  JsonStore(this.fileName);

  final String fileName;
  File? _file;

  Future<void> initialize() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'library_state'));
    await root.create(recursive: true);
    _file = File(p.join(root.path, fileName));
    if (!await _file!.exists()) {
      await _file!.writeAsString('[]');
    }
  }

  Future<List<Map<String, dynamic>>> readList() async {
    await initialize();
    final content = await _file!.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return const <Map<String, dynamic>>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> writeList(List<Map<String, dynamic>> values) async {
    await initialize();
    await _file!.writeAsString(jsonEncode(values));
  }
}
