import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/downloads/image_download_retry.dart';
import 'package:ezvenera/src/utils/json_file_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ezv_robust_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JsonFileStore (REQ-011)', () {
    test('write then read round-trips', () async {
      final store = JsonFileStore(File('${tempDir.path}/cfg.json'));
      await store.write({'a': 1, 'b': 'x', 'nested': {'k': true}});
      final read = await store.read();
      expect(read['a'], 1);
      expect(read['b'], 'x');
      expect((read['nested'] as Map)['k'], isTrue);
    });

    test('missing file yields empty map', () async {
      final store = JsonFileStore(File('${tempDir.path}/missing.json'));
      expect(await store.read(), <String, dynamic>{});
    });

    test('corrupted file yields empty map instead of throwing', () async {
      final file = File('${tempDir.path}/broken.json');
      await file.writeAsString('{"themeMode": "dark"'); // truncated JSON
      final store = JsonFileStore(file);
      expect(await store.read(), <String, dynamic>{});
    });

    test('wrong JSON shape yields empty map instead of throwing', () async {
      final file = File('${tempDir.path}/shape.json');
      await file.writeAsString('["not","an","object"]');
      final store = JsonFileStore(file);
      expect(await store.read(), <String, dynamic>{});
    });

    test('no temp file remains after a successful write', () async {
      final file = File('${tempDir.path}/cfg.json');
      final store = JsonFileStore(file);
      await store.write({'ok': true});
      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });

    test('failed write does not destroy the previous good state', () async {
      // Simulate a crash between tmp creation and rename: the good file must
      // still be readable.
      final file = File('${tempDir.path}/cfg.json');
      final store = JsonFileStore(file);
      await store.write({'version': 1});
      await File('${file.path}.tmp')
          .writeAsString('{"version": 2'); // crashed mid-write
      expect((await store.read())['version'], 1);
    });

    test('concurrent writes are serialized and never lose the tmp file',
        () async {
      // Regression: two fire-and-forget persists racing on a shared ".tmp"
      // made one rename steal the other's temp file (PathNotFoundException
      // observed on device). Per-call temp names + a write queue fix it.
      final file = File('${tempDir.path}/race.json');
      final store = JsonFileStore(file);
      await Future.wait([
        for (var i = 0; i < 20; i++) store.write({'round': i}),
      ]);
      final finalRead = await store.read();
      // The surviving content must be one of the written rounds, and the
      // directory must hold no leftover temp files.
      expect(finalRead['round'], inInclusiveRange(0, 19));
      final leftovers = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('fetchImageWithRetry (REQ-010)', () {
    test('returns bytes on first success without retrying', () async {
      var calls = 0;
      final bytes = await fetchImageWithRetry(
        () async {
          calls += 1;
          return Uint8List.fromList([1, 2, 3]);
        },
        sleep: (_) async {},
      );
      expect(bytes, isNotNull);
      expect(calls, 1);
    });

    test('retries transient failures then succeeds', () async {
      var calls = 0;
      final bytes = await fetchImageWithRetry(
        () async {
          calls += 1;
          if (calls < 3) {
            throw StateError('transient');
          }
          return Uint8List.fromList([9]);
        },
        sleep: (_) async {},
      );
      expect(bytes, isNotNull);
      expect(calls, 3);
    });

    test('returns null after exhausting retries', () async {
      var calls = 0;
      final bytes = await fetchImageWithRetry(
        () async {
          calls += 1;
          throw StateError('permanent');
        },
        sleep: (_) async {},
      );
      expect(bytes, isNull);
      expect(calls, 3); // 1 attempt + 2 retries
    });

    test('empty body counts as a failure and triggers retry', () async {
      var calls = 0;
      final bytes = await fetchImageWithRetry(
        () async {
          calls += 1;
          return Uint8List(0);
        },
        maxRetries: 1,
        sleep: (_) async {},
      );
      expect(bytes, isNull);
      expect(calls, 2);
    });

    test('respects a custom maxRetries', () async {
      var calls = 0;
      await fetchImageWithRetry(
        () async {
          calls += 1;
          throw StateError('always');
        },
        maxRetries: 4,
        sleep: (_) async {},
      );
      expect(calls, 5);
    });
  });
}
