class LocalFavoriteEntry {
  const LocalFavoriteEntry({
    required this.sourceKey,
    required this.comicId,
    required this.title,
    required this.createdAt,
    this.subtitle,
    this.cover,
    this.description,
    this.tags = const <String>[],
    this.isDownloaded = false,
  });

  final String sourceKey;
  final String comicId;
  final String title;
  final String? subtitle;
  final String? cover;
  final String? description;
  final List<String> tags;
  final bool isDownloaded;
  final DateTime createdAt;

  String get key => '$sourceKey@$comicId';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sourceKey': sourceKey,
      'comicId': comicId,
      'title': title,
      'subtitle': subtitle,
      'cover': cover,
      'description': description,
      'tags': tags,
      'isDownloaded': isDownloaded,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory LocalFavoriteEntry.fromJson(Map<String, dynamic> json) {
    return LocalFavoriteEntry(
      sourceKey: json['sourceKey'].toString(),
      comicId: json['comicId'].toString(),
      title: json['title'].toString(),
      subtitle: json['subtitle']?.toString(),
      cover: json['cover']?.toString(),
      description: json['description']?.toString(),
      tags: List<String>.from(json['tags'] ?? const <String>[]),
      isDownloaded: json['isDownloaded'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num).toInt(),
      ),
    );
  }
}
