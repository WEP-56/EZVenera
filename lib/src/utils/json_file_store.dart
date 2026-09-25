import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';

/// JSON file persistence with crash-safe semantics (REQ-011).
///
/// * Writes go to a per-call temp file which is atomically renamed over the
///   target, so a crash mid-write can never destroy the previous state.
/// * Writes are serialized per store instance: concurrent persist calls
///   (settings + app state fire-and-forget writes) would otherwise race on
///   the temp file — one rename steals the other's tmp and the loser throws.
/// * Reads never throw: a missing or corrupted file yields an empty map and
///   a warning log, letting callers fall back to defaults instead of showing
///   a bootstrap error page.
class JsonFileStore {
  JsonFileStore(this.file);

  final File file;
  Future<void> _writeQueue = Future<void>.value();

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

  /// Serialized atomic write. Returns a future that completes when this
  /// write is durable; later writes are queued behind it, never interleaved.
  Future<void> write(Map<String, dynamic> json) => writeJson(json);

  /// Serialized atomic write of a JSON array document (same queue and
  /// self-healing semantics as [write]).
  Future<void> writeList(List<dynamic> values) => writeJson(values);

  Future<void> writeJson(Object? value) {
    final next = _writeQueue.then((_) => _writeAtomic(value));
    // Keep the queue alive even if a write fails: the error is surfaced to
    // the caller of this write only.
    _writeQueue = next.catchError((Object _) {});
    return next;
  }

  /// Reads a JSON array document. Missing, corrupted, or wrong-shape files
  /// yield an empty list (with a warning log) — same contract as [read].
  Future<List<dynamic>> readList() async {
    try {
      if (!await file.exists()) {
        return <dynamic>[];
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded;
      }
      unawaited(
        AppLogger.instance.warning(
          'Config file has unexpected JSON shape, resetting: ${file.path}',
        ),
      );
      return <dynamic>[];
    } catch (error) {
      unawaited(
        AppLogger.instance.warning(
          'Config file is corrupted, falling back to defaults: '
          '${file.path} ($error)',
        ),
      );
      return <dynamic>[];
    }
  }

  Future<void> _writeAtomic(Object? value) async {
    // Unique temp name per write: two stores pointing at the same target, or
    // an external cleanup, can no longer collide on a shared ".tmp" path.
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(value), flush: true);
    try {
      await tmp.rename(file.path);
    } on PathNotFoundException {
      // The temp file vanished between write and rename (external cleanup or
      // a racing sweep). One retry with a fresh temp file; if that also
      // fails the error propagates to the caller.
      final retry = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await retry.writeAsString(jsonEncode(value), flush: true);
      await retry.rename(file.path);
    }
  }
}
