import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'download_models.dart';

class DownloadLibraryStore {
  late Directory rootDirectory;
  late File libraryFile;

  Future<void> initialize() async {
    final supportDirectory = await getApplicationSupportDirectory();
    rootDirectory = Directory(p.join(supportDirectory.path, 'downloads'));
    await rootDirectory.create(recursive: true);
    libraryFile = File(p.join(rootDirectory.path, 'library.json'));
    if (!await libraryFile.exists()) {
      await libraryFile.writeAsString('[]');
    }
  }

  Future<List<DownloadedComic>> loadLibrary() async {
    final content = await libraryFile.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return const <DownloadedComic>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => DownloadedComic.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> saveLibrary(List<DownloadedComic> comics) async {
    await libraryFile.writeAsString(
      jsonEncode(comics.map((comic) => comic.toJson()).toList()),
    );
  }

  Future<void> deleteComic(DownloadedComic comic) async {
    final directory = Directory(comic.basePath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Directory> createComicDirectory(String name) async {
    final sanitized = _sanitize(name);
    var path = p.join(rootDirectory.path, sanitized);
    var index = 1;

    while (await Directory(path).exists()) {
      path = p.join(rootDirectory.path, '${sanitized}_$index');
      index++;
    }

    return Directory(path)..createSync(recursive: true);
  }

  String chapterDirectoryName(String name) => _sanitize(name);

  String _sanitize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[\\/:*?"<>|]').hasMatch(char)) {
        buffer.write('_');
      } else {
        buffer.write(char);
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? 'comic' : result;
  }
}
