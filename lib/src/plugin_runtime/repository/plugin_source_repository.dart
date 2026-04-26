import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import '../parser/plugin_source_parser.dart';
import '../storage/plugin_data_store.dart';

class PluginSourceRepository {
  PluginSourceRepository({
    required this.sourcesPath,
    required this.dataStore,
    required this.parser,
  });

  final String sourcesPath;
  final PluginDataStore dataStore;
  final PluginSourceParser parser;

  Future<void> ensureInitialized() async {
    await Directory(sourcesPath).create(recursive: true);
    await dataStore.ensureInitialized();
  }

  Future<List<PluginSource>> loadAll() async {
    await ensureInitialized();

    final sources = <PluginSource>[];
    await for (final entity in Directory(sourcesPath).list()) {
      if (entity is! File || !entity.path.endsWith('.js')) {
        continue;
      }
      try {
        final source = await parser.parse(
          await entity.readAsString(),
          filePath: entity.path,
        );
        sources.add(source);
      } catch (_) {
        continue;
      }
    }
    return sources;
  }

  Future<PluginSource> installFromString(
    String javascript,
    String fileName, {
    String? installSourceUrl,
  }) async {
    await ensureInitialized();

    final targetFile = await _findAvailableFile(fileName);
    await targetFile.writeAsString(javascript);

    try {
      final source = await parser.parse(javascript, filePath: targetFile.path);
      if (installSourceUrl != null && installSourceUrl.trim().isNotEmpty) {
        source.data['_installSourceUrl'] = installSourceUrl.trim();
        await source.saveData();
      }
      return source;
    } catch (_) {
      await targetFile.delete();
      rethrow;
    }
  }

  Future<void> removeSource(PluginSource source) async {
    final file = File(source.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await dataStore.delete(source.key);
  }

  Future<File> _findAvailableFile(String fileName) async {
    final normalized = fileName.endsWith('.js') ? fileName : '$fileName.js';
    var targetPath = p.join(sourcesPath, normalized);
    var index = 1;

    while (await File(targetPath).exists()) {
      final base = normalized.substring(0, normalized.length - 3);
      targetPath = p.join(sourcesPath, '$base($index).js');
      index++;
    }

    return File(targetPath);
  }
}
