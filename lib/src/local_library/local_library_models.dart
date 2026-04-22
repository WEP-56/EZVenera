class LocalComicFolderEntry {
  const LocalComicFolderEntry({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String path;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'path': path,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory LocalComicFolderEntry.fromJson(Map<String, dynamic> json) {
    return LocalComicFolderEntry(
      id: json['id'].toString(),
      name: json['name'].toString(),
      path: json['path'].toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class LocalLibraryComic {
  const LocalLibraryComic({
    required this.folderId,
    required this.title,
    required this.path,
    required this.coverPath,
    required this.modifiedAt,
    required this.chapters,
  });

  final String folderId;
  final String title;
  final String path;
  final String coverPath;
  final DateTime modifiedAt;
  final List<LocalLibraryChapter> chapters;

  String get comicId => path;
  String get sourceKey => 'local-folder:$folderId';
  int get totalPages =>
      chapters.fold<int>(0, (count, chapter) => count + chapter.pageCount);
}

class LocalLibraryChapter {
  const LocalLibraryChapter({
    required this.id,
    required this.title,
    required this.path,
    required this.pageCount,
  });

  final String id;
  final String title;
  final String path;
  final int pageCount;
}
