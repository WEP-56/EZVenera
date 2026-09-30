import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/library/history_controller.dart';
import 'package:ezvenera/src/library/history_models.dart';
import 'package:ezvenera/src/pages/comic_details_page.dart';
import 'package:ezvenera/src/plugin_runtime/models.dart';
import 'package:ezvenera/src/reader/chapter_order.dart';

/// Read/unread marks on the details page used to be inferred from a single
/// "last read chapter" pointer: everything before it counted as read. That is
/// wrong for the two ways people actually read — jumping into the middle of a
/// story marked the whole first half read, and reading backwards marked the
/// chapters still waiting to be opened while leaving the opened ones unread.
/// The reader now records every chapter it opens, so a mark means "opened".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('ezv_read_state_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => supportDir.path,
        );
    await HistoryController.instance.initialize();
  });

  tearDownAll(() async {
    await supportDir.delete(recursive: true);
  });

  group('ReadingHistoryEntry read chapters', () {
    test('survive the JSON round-trip', () {
      final entry = ReadingHistoryEntry(
        sourceKey: 'src',
        comicId: 'comic',
        title: 't',
        chapterId: 'c3',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        readChapterIds: const {'c1', 'c2', 'c3'},
      );

      final decoded = ReadingHistoryEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.readChapterIds, unorderedEquals(['c1', 'c2', 'c3']));
      expect(decoded.chapterId, 'c3');
    });

    test('an entry written by an older build seeds its own chapter', () {
      final legacy = ReadingHistoryEntry.fromJson(<String, dynamic>{
        'sourceKey': 'src',
        'comicId': 'comic',
        'title': 't',
        'chapterId': 'c7',
        'timestamp': 1000,
      });

      expect(legacy.readChapterIds, unorderedEquals(['c7']));
    });

    test('an entry that never reached a chapter has nothing read', () {
      final legacy = ReadingHistoryEntry.fromJson(<String, dynamic>{
        'sourceKey': 'src',
        'comicId': 'comic',
        'title': 't',
        'timestamp': 1000,
      });

      expect(legacy.readChapterIds, isEmpty);
    });
  });

  group('HistoryController accumulates per chapter', () {
    test('opening a later chapter keeps the earlier one marked', () async {
      final base = _entry('accumulate', 'c1', at: 1);
      await HistoryController.instance.record(base);
      await HistoryController.instance.record(
        _entry('accumulate', 'c3', at: 2, page: 12),
      );

      final stored = HistoryController.instance.find('src', 'accumulate')!;
      expect(stored.readChapterIds, unorderedEquals(['c1', 'c3']));
      expect(stored.chapterId, 'c3');
      expect(stored.page, 12);
    });

    test(
      'turning pages inside a chapter does not grow or lose the set',
      () async {
        await HistoryController.instance.record(_entry('pages', 'c2', at: 1));
        await HistoryController.instance.record(
          _entry('pages', 'c2', at: 2, page: 5),
        );
        await HistoryController.instance.record(
          _entry('pages', 'c2', at: 3, page: 6),
        );

        expect(
          HistoryController.instance.find('src', 'pages')!.readChapterIds,
          unorderedEquals(['c2']),
        );
      },
    );

    test(
      'a merged backup unions both devices without losing the bookmark',
      () async {
        await HistoryController.instance.record(_entry('merged', 'c1', at: 10));
        await HistoryController.instance.mergeEntries([
          _entry('merged', 'c4', at: 20),
        ]);

        final stored = HistoryController.instance.find('src', 'merged')!;
        expect(stored.readChapterIds, unorderedEquals(['c1', 'c4']));
        expect(stored.chapterId, 'c4');
      },
    );

    test(
      'accumulated chapters are persisted, not just held in memory',
      () async {
        await HistoryController.instance.record(
          _entry('persisted', 'c1', at: 1),
        );
        await HistoryController.instance.record(
          _entry('persisted', 'c2', at: 2),
        );

        final onDisk = HistoryController.instance.entries
            .where((entry) => entry.comicId == 'persisted')
            .single;
        expect(onDisk.readChapterIds, unorderedEquals(['c1', 'c2']));

        final raw =
            jsonDecode(
                  File(
                    '${supportDir.path}/library_state/history.json',
                  ).readAsStringSync(),
                )
                as List<dynamic>;
        final persisted = raw.cast<Map<String, dynamic>>().firstWhere(
          (item) => item['comicId'] == 'persisted',
        );
        expect(
          ReadingHistoryEntry.fromJson(persisted).readChapterIds,
          unorderedEquals(['c1', 'c2']),
        );
      },
    );
  });

  group('Details page marks only chapters that were opened', () {
    final chapters = PluginComicChapters.flat(const {
      'c1': '第1话',
      'c2': '第2话',
      'c3': '第3话',
      'c4': '第4话',
      'c5': '第5话',
    });

    testWidgets('forward display marks exactly the opened chapters', (
      tester,
    ) async {
      await _pumpChapters(
        tester,
        chapters: chapters,
        readChapterIds: const {'c1', 'c2'},
        readChapterId: 'c2',
      );

      expect(_readMarks(tester, const ['c1', 'c2', 'c3', 'c4', 'c5']), {
        'c1',
        'c2',
      });
      expect(_trailingIcon(tester, 'c2'), Icons.play_circle_outline);
    });

    testWidgets('reversing the display marks the same chapters', (
      tester,
    ) async {
      await _pumpChapters(
        tester,
        chapters: chapters,
        reversed: true,
        readChapterIds: const {'c1', 'c2'},
        readChapterId: 'c2',
      );

      // Reading backwards shows 5,4,3,2,1; the marks still belong to 2 and 1.
      expect(_displayedOrder(tester), ['第5话', '第4话', '第3话', '第2话', '第1话']);
      expect(_readMarks(tester, const ['c1', 'c2', 'c3', 'c4', 'c5']), {
        'c1',
        'c2',
      });
    });

    testWidgets('jumping into the middle marks nothing before it', (
      tester,
    ) async {
      await _pumpChapters(
        tester,
        chapters: chapters,
        readChapterIds: const {'c4'},
        readChapterId: 'c4',
      );

      expect(_readMarks(tester, const ['c1', 'c2', 'c3', 'c4', 'c5']), {'c4'});
    });

    testWidgets('an unknown chapter id marks nothing', (tester) async {
      await _pumpChapters(
        tester,
        chapters: chapters,
        readChapterIds: const {'gone'},
      );

      expect(_readMarks(tester, const ['c1', 'c2', 'c3', 'c4', 'c5']), isEmpty);
    });

    testWidgets('marks cross group boundaries', (tester) async {
      final grouped = PluginComicChapters.grouped(const {
        '卷一': {'a1': '第1话', 'a2': '第2话'},
        '卷二': {'b1': '第3话'},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChaptersView(
                chapters: grouped,
                reversed: false,
                mode: ChapterDisplayMode.list,
                readChapterIds: const {'a1', 'b1'},
                onChapterSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      for (final group in ['卷一', '卷二']) {
        await tester.tap(find.text(group));
        await tester.pumpAndSettle();
      }

      expect(_readMarks(tester, const ['a1', 'a2', 'b1']), {'a1', 'b1'});
    });
  });
}

ReadingHistoryEntry _entry(
  String comicId,
  String chapterId, {
  required int at,
  int page = 1,
}) {
  return ReadingHistoryEntry(
    sourceKey: 'src',
    comicId: comicId,
    title: '标题',
    chapterId: chapterId,
    page: page,
    timestamp: DateTime.fromMillisecondsSinceEpoch(at),
  );
}

Future<void> _pumpChapters(
  WidgetTester tester, {
  required PluginComicChapters chapters,
  required Set<String> readChapterIds,
  bool reversed = false,
  String? readChapterId,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ChaptersView(
            chapters: chapters,
            reversed: reversed,
            mode: ChapterDisplayMode.list,
            readChapterId: readChapterId,
            readChapterIds: readChapterIds,
            onChapterSelected: (_) {},
          ),
        ),
      ),
    ),
  );
}

Finder _tile(String id) =>
    find.ancestor(of: find.text(id), matching: find.byType(ListTile));

/// A read chapter is drawn dimmed; the unread ones keep the full-strength
/// foreground. This is the only read-state signal outside E-Ink mode.
Set<String> _readMarks(WidgetTester tester, Iterable<String> ids) {
  final scheme = Theme.of(tester.element(_tile(ids.first))).colorScheme;
  final readColor = scheme.onSurfaceVariant.withValues(alpha: 0.6);
  final marks = <String>{};
  for (final id in ids) {
    final title = tester.widget<ListTile>(_tile(id)).title! as Text;
    if (title.style?.color == readColor) {
      marks.add(id);
    }
  }
  return marks;
}

IconData? _trailingIcon(WidgetTester tester, String id) =>
    (tester.widget<ListTile>(_tile(id)).trailing! as Icon).icon;

List<String> _displayedOrder(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title! as Text).data!)
    .toList();
