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

  String get key => '$sourceKey@$comicId';

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
    );
  }
}
