import '../state/app_state_controller.dart';

String _chapterOrderKey(String sourceKey, String comicId) {
  final source = Uri.encodeComponent(sourceKey);
  final comic = Uri.encodeComponent(comicId);
  return 'reader.chapterOrder.$source.$comic.reversed';
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
