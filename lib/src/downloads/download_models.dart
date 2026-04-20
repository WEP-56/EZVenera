class DownloadedComic {
  const DownloadedComic({
    required this.sourceKey,
    required this.comicId,
    required this.title,
    required this.basePath,
    required this.createdAt,
    required this.chapters,
    this.subtitle,
    this.description,
    this.coverPath,
    this.tags = const <String>[],
  });

  final String sourceKey;
  final String comicId;
  final String title;
  final String? subtitle;
  final String? description;
  final String? coverPath;
  final List<String> tags;
  final String basePath;
  final DateTime createdAt;
  final List<DownloadedChapter> chapters;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sourceKey': sourceKey,
      'comicId': comicId,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'coverPath': coverPath,
      'tags': tags,
      'basePath': basePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    };
  }

  factory DownloadedComic.fromJson(Map<String, dynamic> json) {
    return DownloadedComic(
      sourceKey: json['sourceKey'].toString(),
      comicId: json['comicId'].toString(),
      title: json['title'].toString(),
      subtitle: json['subtitle']?.toString(),
      description: json['description']?.toString(),
      coverPath: json['coverPath']?.toString(),
      tags: List<String>.from(json['tags'] ?? const <String>[]),
      basePath: json['basePath'].toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num).toInt(),
      ),
      chapters: (json['chapters'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (chapter) =>
                DownloadedChapter.fromJson(Map<String, dynamic>.from(chapter)),
          )
          .toList(),
    );
  }
}

class DownloadedChapter {
  const DownloadedChapter({
    required this.id,
    required this.title,
    required this.path,
    required this.pageCount,
  });

  final String id;
  final String title;
  final String path;
  final int pageCount;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'path': path,
      'pageCount': pageCount,
    };
  }

  factory DownloadedChapter.fromJson(Map<String, dynamic> json) {
    return DownloadedChapter(
      id: json['id'].toString(),
      title: json['title'].toString(),
      path: json['path'].toString(),
      pageCount: (json['pageCount'] as num).toInt(),
    );
  }
}

enum DownloadTaskStatus { queued, running, completed, failed, cancelled }

class ChapterDownloadRequest {
  const ChapterDownloadRequest({required this.id, required this.title});

  final String? id;
  final String title;
}
