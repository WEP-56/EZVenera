import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/library/json_store.dart';
import 'package:ezvenera/src/plugin_runtime/storage/plugin_data_store.dart';
import 'package:ezvenera/src/utils/json_file_store.dart';

/// Regression coverage for the F-01 audit finding: library and plugin
/// storage used bare writeAsString; they must now share JsonFileStore's
/// atomic, serialized, self-healing semantics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('ezv_f01_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => supportDir.path,
        );
  });

  tearDownAll(() async {
    await supportDir.delete(recursive: true);
  });

  group('JsonStore (F-01: atomic, self-healing)', () {
    test('writeList then readList round-trips', () async {
      final store = JsonStore('favorites.json');
      await store.writeList([
        {'id': 'a', 'title': 'x'},
        {'id': 'b', 'title': 'y'},
      ]);
      final read = await store.readList();
      expect(read, hasLength(2));
      expect(read[0]['id'], 'a');
    });

    test('corrupted file yields empty list and rewrites healthily', () async {
      final store = JsonStore('history.json');
      await store.writeList([{'id': 'a'}]);
      // Simulate an external truncation.
      File('${supportDir.path}/library_state/history.json')
          .writeAsStringSync('{"trunc');
      expect(await store.readList(), isEmpty);
      // A subsequent write heals the file for the next reader.
      await store.writeList([{'id': 'b'}]);
      final healed = JsonStore('history.json');
      expect((await healed.readList()).first['id'], 'b');
    });

    test('concurrent writes are serialized (no tmp races)', () async {
      final store = JsonStore('folders.json');
      await Future.wait([
        for (var i = 0; i < 10; i++)
          store.writeList([{'round': i}]),
      ]);
      final read = await store.readList();
      expect(read, hasLength(1));
      expect((read.first['round'] as int), inInclusiveRange(0, 9));
      final leftovers = Directory('${supportDir.path}/library_state')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('PluginDataStore (F-01: atomic per-source storage)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ezv_pdata_test');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('read/write round-trips per source key', () async {
      final store = PluginDataStore(root.path);
      await store.write('src_a', {'token': 't1'});
      await store.write('src_b', {'token': 't2'});
      expect((await store.read('src_a'))['token'], 't1');
      expect((await store.read('src_b'))['token'], 't2');
    });

    test('concurrent writes to the same source stay serialized', () async {
      final store = PluginDataStore(root.path);
      await Future.wait([
        for (var i = 0; i < 10; i++) store.write('src', {'round': i}),
      ]);
      final read = await store.read('src');
      expect((read['round'] as int), inInclusiveRange(0, 9));
      final leftovers = root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('corrupted file falls back to empty map', () async {
      final store = PluginDataStore(root.path);
      await store.write('src', {'ok': true});
      File('${root.path}/src.json').writeAsStringSync('nope{');
      expect(await store.read('src'), <String, dynamic>{});
    });

    test('delete removes the file', () async {
      final store = PluginDataStore(root.path);
      await store.write('src', {'k': 'v'});
      await store.delete('src');
      expect(await store.read('src'), <String, dynamic>{});
    });
  });

  group('JsonFileStore list support', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ezv_list_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writeList/readList round-trips and self-heals', () async {
      final store = JsonFileStore(File('${tempDir.path}/list.json'));
      await store.writeList([1, 'two', {'three': 3}]);
      expect(await store.readList(), hasLength(3));

      File('${tempDir.path}/list.json').writeAsStringSync('[broken');
      expect(await store.readList(), isEmpty);
    });
  });
}
