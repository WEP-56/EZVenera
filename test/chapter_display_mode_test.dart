import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/reader/chapter_order.dart';
import 'package:ezvenera/src/state/app_state_controller.dart';

/// Covers the per-comic chapter display mode persistence (REQ-2 of
/// docs/changes/chapter-grid-view.md). Pure Dart: AppStateController only
/// touches its in-memory map here — initialize()/persistence is exercised
/// by the flutter_test suites with the path_provider mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to list for comics that never toggled the mode', () {
    expect(
      chapterDisplayModeFor('source', 'comic-no-mode'),
      ChapterDisplayMode.list,
    );
  });

  test('set/get round-trips for both modes', () async {
    await setChapterDisplayModeFor('s', 'c1', ChapterDisplayMode.grid);
    expect(chapterDisplayModeFor('s', 'c1'), ChapterDisplayMode.grid);

    await setChapterDisplayModeFor('s', 'c1', ChapterDisplayMode.list);
    expect(chapterDisplayModeFor('s', 'c1'), ChapterDisplayMode.list);

    await setChapterDisplayModeFor('s', 'c2', ChapterDisplayMode.grid);
    expect(chapterDisplayModeFor('s', 'c2'), ChapterDisplayMode.grid);
    // Other comics are unaffected.
    expect(chapterDisplayModeFor('s', 'c1'), ChapterDisplayMode.list);
  });

  test('special characters in source keys stay isolated', () async {
    await setChapterDisplayModeFor(
      'source.with.dots/special',
      'comic/1:2',
      ChapterDisplayMode.grid,
    );
    expect(
      chapterDisplayModeFor('source.with.dots/special', 'comic/1:2'),
      ChapterDisplayMode.grid,
    );
    expect(
      chapterDisplayModeFor('source', 'comic'),
      ChapterDisplayMode.list,
    );
  });

  test('chapter order reversed preference is unaffected', () async {
    await setChapterOrderReversedFor('s', 'c1', true);
    expect(isChapterOrderReversedFor('s', 'c1'), isTrue);
    await setChapterDisplayModeFor('s', 'c1', ChapterDisplayMode.grid);
    // Mode toggle must not clobber the order preference.
    expect(isChapterOrderReversedFor('s', 'c1'), isTrue);
    expect(chapterDisplayModeFor('s', 'c1'), ChapterDisplayMode.grid);
  });

  test('AppStateController state is keyed independently', () {
    // The two preferences must use distinct keys.
    expect(
      AppStateController.instance.getString(
        'reader.chapterDisplay.s.c1.mode',
      ),
      'grid',
    );
    expect(
      AppStateController.instance.getString(
        'reader.chapterOrder.s.c1.reversed',
      ),
      '1',
    );
  });
}
