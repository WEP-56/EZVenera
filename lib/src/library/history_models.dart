class ReadingHistoryEntry {
  const ReadingHistoryEntry({
    required this.sourceKey,
    required this.comicId,
    required this.title,
    required this.timestamp,
    this.subtitle,
    this.cover,
    this.chapterId,
    this.chapterTitle,
    this.page = 1,
    this.isLocal = false,
    this.localComicPath,
    this.localFolderId,
    this.readChapterIds = const <String>{},
  });

  final String sourceKey;
  final String comicId;
  final String title;
  final String? subtitle;
  final String? cover;
  final String? chapterId;
  final String? chapterTitle;
  final int page;
  final DateTime timestamp;
  final bool isLocal;
  final String? localComicPath;
  final String? localFolderId;

  /// Every chapter the reader has opened, in no particular order. Read state
  /// has to be recorded per chapter: the previous scheme inferred it from a
  /// single "last read" pointer, which marked chapters read that were never
  /// opened and vice versa, and flipped entirely for reverse-order reading.
  final Set<String> readChapterIds;

  String get key => '$sourceKey@$comicId';

  ReadingHistoryEntry copyWith({Set<String>? readChapterIds}) {
    return ReadingHistoryEntry(
      sourceKey: sourceKey,
      comicId: comicId,
      title: title,
      subtitle: subtitle,
      cover: cover,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      page: page,
      timestamp: timestamp,
      isLocal: isLocal,
      localComicPath: localComicPath,
      localFolderId: localFolderId,
      readChapterIds: readChapterIds ?? this.readChapterIds,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sourceKey': sourceKey,
      'comicId': comicId,
      'title': title,
      'subtitle': subtitle,
      'cover': cover,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'page': page,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isLocal': isLocal,
      'localComicPath': localComicPath,
      'localFolderId': localFolderId,
      'readChapterIds': readChapterIds.toList(),
    };
  }

  factory ReadingHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ReadingHistoryEntry(
      sourceKey: json['sourceKey'].toString(),
      comicId: json['comicId'].toString(),
      title: json['title'].toString(),
      subtitle: json['subtitle']?.toString(),
      cover: json['cover']?.toString(),
      chapterId: json['chapterId']?.toString(),
      chapterTitle: json['chapterTitle']?.toString(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as num).toInt(),
      ),
      isLocal: json['isLocal'] == true,
      localComicPath: json['localComicPath']?.toString(),
      localFolderId: json['localFolderId']?.toString(),
      readChapterIds: _readChapterIds(json),
    );
  }

  /// Entries written by older builds carry no such list; the chapter they
  /// point at was certainly opened, so that alone becomes the seeded history.
  static Set<String> _readChapterIds(Map<String, dynamic> json) {
    final stored = (json['readChapterIds'] as List?)?.map((e) => '$e').toSet();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final chapterId = json['chapterId']?.toString();
    if (chapterId == null || chapterId.isEmpty) {
      return const <String>{};
    }
    return <String>{chapterId};
  }
}
