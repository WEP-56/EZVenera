import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/plugin_runtime/repository/source_index.dart';

void main() {
  group('parseSourceIndex (REQ-014)', () {
    test('parses the upstream index.json shape', () {
      final entries = parseSourceIndex('''
[
  {"name": "拷贝漫画", "fileName": "copy_manga.js", "key": "copy_manga", "version": "1.4.2"},
  {"name": "Komiic", "fileName": "komiic.js", "key": "Komiic", "version": "1.0.3"}
]
''');
      expect(entries, hasLength(2));
      expect(entries[0].name, '拷贝漫画');
      expect(entries[0].key, 'copy_manga');
      expect(entries[0].version, '1.4.2');
      expect(entries[0].fileName, 'copy_manga.js');
    });

    test('accepts the filename alias and url overrides', () {
      final entries = parseSourceIndex('''
[
  {"name": "A", "key": "a", "filename": "a.js", "version": "1.0"},
  {"name": "B", "key": "b", "url": "https://example.com/b.js", "version": "1.1"}
]
''');
      expect(entries[0].fileName, 'a.js');
      expect(entries[1].url, 'https://example.com/b.js');
    });

    test('throws on invalid JSON and on non-list payloads', () {
      expect(
        () => parseSourceIndex('{"not": "a list"}'),
        throwsStateError,
      );
      expect(() => parseSourceIndex('broken{'), throwsStateError);
    });

    test('skips malformed rows but keeps valid ones', () {
      final entries = parseSourceIndex('''
[
  "a bare string",
  {"no": "identifiers"},
  {"name": "ok", "key": "ok", "version": "1.0", "fileName": "ok.js"}
]
''');
      expect(entries, hasLength(1));
      expect(entries[0].key, 'ok');
    });

    test('empty list parses to zero entries', () {
      expect(parseSourceIndex('[]'), isEmpty);
    });
  });

  group('SourceIndexEntry resolution', () {
    test('resolvedLocalPath joins the index directory', () {
      final entry = SourceIndexEntry.fromMap({
        'name': 'x',
        'key': 'x',
        'version': '1.0',
        'fileName': 'x.js',
      });
      expect(
        entry.resolvedLocalPath('/device/Download/sources'),
        '/device/Download/sources/x.js',
      );
    });

    test('resolvedLocalPath is null without fileName', () {
      final entry = SourceIndexEntry.fromMap({
        'name': 'y',
        'key': 'y',
        'version': '1.0',
        'url': 'https://example.com/y.js',
      });
      expect(entry.resolvedLocalPath('/tmp'), isNull);
    });

    test('resolvedUrl keeps absolute urls and resolves relative fileName',
        () {
      final withUrl = SourceIndexEntry.fromMap({
        'key': 'a',
        'url': 'https://cdn.example.com/a.js',
      });
      expect(withUrl.resolvedUrl('https://example.com/repo/index.json'),
          'https://cdn.example.com/a.js');

      final withFile = SourceIndexEntry.fromMap({
        'key': 'b',
        'fileName': 'b.js',
      });
      expect(withFile.resolvedUrl('https://example.com/repo/index.json'),
          'https://example.com/repo/b.js');
    });

    test('resolvedLocalPath exists check drives the local install decision',
        () async {
      final dir = await Directory.systemTemp.createTemp('ezv_local_index');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/present.js').writeAsStringSync('// source');
      final present = SourceIndexEntry.fromMap({
        'key': 'p',
        'fileName': 'present.js',
      });
      final missing = SourceIndexEntry.fromMap({
        'key': 'm',
        'fileName': 'missing.js',
      });
      expect(
        File(present.resolvedLocalPath(dir.path)!).existsSync(),
        isTrue,
      );
      expect(
        File(missing.resolvedLocalPath(dir.path)!).existsSync(),
        isFalse,
      );
    });
  });
}
