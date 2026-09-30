import '../plugin_runtime/models.dart';
import '../settings/settings_controller.dart';
import '../state/app_state_controller.dart';

/// How the chapter section of the details page lays out chapters.
enum ChapterDisplayMode { list, grid }

String _chapterOrderKey(String sourceKey, String comicId) {
  final source = Uri.encodeComponent(sourceKey);
  final comic = Uri.encodeComponent(comicId);
  return 'reader.chapterOrder.$source.$comic.reversed';
}

String _chapterDisplayKey(String sourceKey, String comicId) {
  final source = Uri.encodeComponent(sourceKey);
  final comic = Uri.encodeComponent(comicId);
  return 'reader.chapterDisplay.$source.$comic.mode';
}

/// Per-comic chapter display mode. Comics that were never toggled default
/// to list (the historical look) — except in E-Ink mode, where the compact
/// grid is the default (fewer, denser refreshes).
ChapterDisplayMode chapterDisplayModeFor(String sourceKey, String comicId) {
  final stored = AppStateController.instance.getString(
    _chapterDisplayKey(sourceKey, comicId),
  );
  if (stored != null && stored.isNotEmpty) {
    return stored == 'grid' ? ChapterDisplayMode.grid : ChapterDisplayMode.list;
  }
  return SettingsController.instance.einkMode
      ? ChapterDisplayMode.grid
      : ChapterDisplayMode.list;
}

Future<void> setChapterDisplayModeFor(
  String sourceKey,
  String comicId,
  ChapterDisplayMode mode,
) {
  return AppStateController.instance.setString(
    _chapterDisplayKey(sourceKey, comicId),
    mode.name,
  );
}

bool isChapterOrderReversedFor(String sourceKey, String comicId) {
  return AppStateController.instance.getInt(
        _chapterOrderKey(sourceKey, comicId),
      ) ==
      1;
}

Future<void> setChapterOrderReversedFor(
  String sourceKey,
  String comicId,
  bool reversed,
) {
  return AppStateController.instance.setInt(
    _chapterOrderKey(sourceKey, comicId),
    reversed ? 1 : 0,
  );
}

List<MapEntry<String, String>> orderedChapterEntries(
  Map<String, String> chapters,
  bool reversed,
) {
  final entries = chapters.entries.toList();
  return reversed ? entries.reversed.toList() : entries;
}

List<MapEntry<String, Map<String, String>>> orderedChapterGroups(
  Map<String, Map<String, String>> groups,
  bool reversed,
) {
  final entries = groups.entries.toList();
  return reversed ? entries.reversed.toList() : entries;
}

/// Each chapter's position in the story's own order: group order first, then
/// insertion order inside the group.
///
/// Read state must be judged against this rather than against the displayed
/// list: the displayed list is reversed on demand, which would flip the
/// before/after comparison, and a grouped comic is rendered one group at a
/// time, which would hide every chapter read before the current group.
Map<String, int> canonicalChapterRanks(PluginComicChapters chapters) {
  final groups = chapters.isGrouped
      ? chapters.groupedChapters!.values
      : [chapters.chapters!];
  final ranks = <String, int>{};
  for (final group in groups) {
    for (final id in group.keys) {
      ranks[id] = ranks.length;
    }
  }
  return ranks;
}

/// A chapter is read when it comes before the chapter the reader last stopped
/// at. Unknown either side means nothing is marked read.
bool chapterIsRead({int? rank, required int? readRank}) {
  return rank != null && readRank != null && rank < readRank;
}
