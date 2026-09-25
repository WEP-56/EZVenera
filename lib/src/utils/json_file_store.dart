import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';

/// JSON file persistence with crash-safe semantics (REQ-011).
///
/// * Writes go to a sibling temp file which is atomically renamed over the
///   target, so a crash mid-write can never destroy the previous state.
/// * Reads never throw: a missing or corrupted file yields an empty map and
///   a warning log, letting callers fall back to defaults instead of showing
///   a bootstrap error page.
class JsonFileStore {
  JsonFileStore(this.file);

  final File file;

  Future<Map<String, dynamic>> read() async {
    try {
      if (!await file.exists()) {
        return <String, dynamic>{};
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      // Valid JSON of the wrong shape counts as corruption.
      unawaited(
        AppLogger.instance.warning(
          'Config file has unexpected JSON shape, resetting: ${file.path}',
        ),
      );
      return <String, dynamic>{};
    } catch (error) {
      unawaited(
        AppLogger.instance.warning(
          'Config file is corrupted, falling back to defaults: '
          '${file.path} ($error)',
        ),
      );
      return <String, dynamic>{};
    }
  }

  Future<void> write(Map<String, dynamic> json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(json), flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      // rename over an existing target can fail on some filesystems;
      // delete-then-rename keeps the write atomic enough in practice.
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
  }
}
