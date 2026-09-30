import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/plugin_runtime/models.dart';
import 'package:ezvenera/src/reader/chapter_order.dart';

/// Covers the read/unread marking on the details page, which must follow the
/// story's own order. Marking used to compare positions inside the displayed
/// list, so a reversed display inverted the split and a grouped comic only
/// marked chapters read inside the current chapter's own group.
void main() {
  group('canonicalChapterRanks', () {
    test('flat comics rank by insertion order', () {
      final chapters = PluginComicChapters.flat(const {
        'c1': '第1话',
        'c2': '第2话',
        'c3': '第3话',
      });

      expect(canonicalChapterRanks(chapters), const {
        'c1': 0,
        'c2': 1,
        'c3': 2,
      });
    });

    test('grouped comics keep one continuous rank across groups', () {
      final chapters = PluginComicChapters.grouped(const {
        '卷一': {'a1': '1', 'a2': '2'},
        '卷二': {'b1': '1', 'b2': '2'},
      });

      expect(canonicalChapterRanks(chapters), const {
        'a1': 0,
        'a2': 1,
        'b1': 2,
        'b2': 3,
      });
    });
  });

  group('chapterIsRead', () {
    test('everything before the current chapter counts as read', () {
      expect(chapterIsRead(rank: 0, readRank: 2), isTrue);
      expect(chapterIsRead(rank: 1, readRank: 2), isTrue);
      expect(chapterIsRead(rank: 2, readRank: 2), isFalse);
      expect(chapterIsRead(rank: 3, readRank: 2), isFalse);
    });

    test('an unknown chapter on either side marks nothing read', () {
      expect(chapterIsRead(rank: 0, readRank: null), isFalse);
      expect(chapterIsRead(rank: null, readRank: 2), isFalse);
    });

    test('reversing the display does not change which chapters are read', () {
      const ids = ['c1', 'c2', 'c3', 'c4'];
      final flat = PluginComicChapters.flat(const {
        'c1': '1',
        'c2': '2',
        'c3': '3',
        'c4': '4',
      });
      final ranks = canonicalChapterRanks(flat);
      final readRank = ranks['c3'];

      for (final reversed in [false, true]) {
        final displayed = orderedChapterEntries(flat.chapters!, reversed);
        expect(
          displayed.map((entry) => entry.key).toList(),
          reversed ? ids.reversed.toList() : ids,
        );
        expect(
          displayed
              .where(
                (entry) =>
                    chapterIsRead(rank: ranks[entry.key], readRank: readRank),
              )
              .map((entry) => entry.key)
              .toList(),
          unorderedEquals(['c1', 'c2']),
          reason: 'reversed: $reversed',
        );
      }
    });

    test('chapters in earlier groups are read, later groups are not', () {
      final grouped = PluginComicChapters.grouped(const {
        '卷一': {'a1': '1', 'a2': '2'},
        '卷二': {'b1': '1'},
        '卷三': {'c1': '1'},
      });
      final ranks = canonicalChapterRanks(grouped);
      final readRank = ranks['b1'];

      expect(
        ranks.keys.where(
          (id) => chapterIsRead(rank: ranks[id], readRank: readRank),
        ),
        unorderedEquals(['a1', 'a2']),
      );
    });
  });
}
