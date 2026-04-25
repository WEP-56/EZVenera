import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../library/json_store.dart';
import '../utils/natural_sort.dart';
import 'local_library_models.dart';

class LocalLibraryController extends ChangeNotifier {
  LocalLibraryController._();

  static final LocalLibraryController instance = LocalLibraryController._();

  static const _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.jpe',
    '.avif',
  };

  final JsonStore _store = JsonStore('local_comic_folders.json');
  List<LocalComicFolderEntry> _folders = const <LocalComicFolderEntry>[];
  final Map<String, List<LocalLibraryComic>> _comicsByFolderId =
      <String, List<LocalLibraryComic>>{};
  final Map<String, String> _errorsByFolderId = <String, String>{};
  final Set<String> _loadingFolderIds = <String>{};
  bool _initialized = false;

  List<LocalComicFolderEntry> get folders =>
      List<LocalComicFolderEntry>.unmodifiable(_folders);

  List<LocalLibraryComic> comicsFor(String folderId) {
    return List<LocalLibraryComic>.unmodifiable(
      _comicsByFolderId[folderId] ?? const <LocalLibraryComic>[],
    );
  }

  String? errorFor(String folderId) => _errorsByFolderId[folderId];

  bool isLoading(String folderId) => _loadingFolderIds.contains(folderId);

  LocalComicFolderEntry? folderById(String folderId) {
    for (final folder in _folders) {
      if (folder.id == folderId) {
        return folder;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final raw = await _store.readList();
    _folders = raw.map(LocalComicFolderEntry.fromJson).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _initialized = true;
    notifyListeners();
    await refreshAll();
  }

  Future<LocalComicFolderEntry> addFolder(String path) async {
    await initialize();
    final normalizedPath = _normalizePath(path);
    for (final folder in _folders) {
      if (_samePath(folder.path, normalizedPath)) {
        await refreshFolder(folder.id);
        return folder;
      }
    }

    final directory = Directory(normalizedPath);
    if (!await directory.exists()) {
      throw StateError('Folder not found.');
    }

    final entry = LocalComicFolderEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _displayNameForPath(normalizedPath),
      path: normalizedPath,
      createdAt: DateTime.now(),
    );
    _folders = [..._folders, entry];
    await _persist();
    notifyListeners();
    await refreshFolder(entry.id);
    return entry;
  }

  Future<void> removeFolder(String folderId) async {
    await initialize();
    _folders = _folders.where((folder) => folder.id != folderId).toList();
    _comicsByFolderId.remove(folderId);
    _errorsByFolderId.remove(folderId);
    _loadingFolderIds.remove(folderId);
    await _persist();
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await initialize();
    for (final folder in _folders) {
      await refreshFolder(folder.id);
    }
  }

  Future<void> refreshFolder(String folderId) async {
    await initialize();
    final folder = folderById(folderId);
    if (folder == null) {
      return;
    }

    _loadingFolderIds.add(folderId);
    _errorsByFolderId.remove(folderId);
    notifyListeners();

    try {
      final comics = await _scanFolder(folder);
      _comicsByFolderId[folderId] = comics;
    } catch (error) {
      _comicsByFolderId[folderId] = const <LocalLibraryComic>[];
      _errorsByFolderId[folderId] = error.toString();
    } finally {
      _loadingFolderIds.remove(folderId);
      notifyListeners();
    }
  }

  Future<LocalLibraryComic?> scanComicPath(
    String comicPath, {
    String folderId = 'history',
  }) async {
    return _scanComicDirectory(
      Directory(_normalizePath(comicPath)),
      folderId: folderId,
    );
  }

  Future<void> _persist() {
    return _store.writeList(_folders.map((folder) => folder.toJson()).toList());
  }

  Future<List<LocalLibraryComic>> _scanFolder(
    LocalComicFolderEntry folder,
  ) async {
    final directory = Directory(folder.path);
    if (!await directory.exists()) {
      throw StateError('Folder not found: ${folder.path}');
    }

    final childDirectories = <Directory>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory && !_isHiddenName(entity.path)) {
        childDirectories.add(entity);
      }
    }
    childDirectories.sort((a, b) => naturalComparePaths(a.path, b.path));

    final comics = <LocalLibraryComic>[];
    for (final child in childDirectories) {
      final comic = await _scanComicDirectory(child, folderId: folder.id);
      if (comic != null) {
        comics.add(comic);
      }
    }

    if (comics.isEmpty) {
      final selfComic = await _scanComicDirectory(
        directory,
        folderId: folder.id,
        titleOverride: folder.name,
      );
      if (selfComic != null) {
        comics.add(selfComic);
      }
    }

    comics.sort((a, b) {
      final timeCompare = b.modifiedAt.compareTo(a.modifiedAt);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.title.compareTo(b.title);
    });
    return comics;
  }

  Future<LocalLibraryComic?> _scanComicDirectory(
    Directory directory, {
    required String folderId,
    String? titleOverride,
  }) async {
    if (!await directory.exists()) {
      return null;
    }

    final rootImages = <File>[];
    final childDirectories = <Directory>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isImageFile(entity.path)) {
        rootImages.add(entity);
      } else if (entity is Directory && !_isHiddenName(entity.path)) {
        childDirectories.add(entity);
      }
    }

    rootImages.sort((a, b) => naturalComparePaths(a.path, b.path));
    childDirectories.sort((a, b) => naturalComparePaths(a.path, b.path));

    final chapters = <LocalLibraryChapter>[];
    for (final child in childDirectories) {
      final images = await _listImageFiles(child);
      if (images.isEmpty) {
        continue;
      }
      chapters.add(
        LocalLibraryChapter(
          id: p.basename(child.path),
          title: p.basename(child.path),
          path: child.path,
          pageCount: images.length,
        ),
      );
    }

    if (chapters.isEmpty && rootImages.isEmpty) {
      return null;
    }

    if (chapters.isEmpty) {
      chapters.add(
        LocalLibraryChapter(
          id: 'main',
          title: 'Main',
          path: directory.path,
          pageCount: rootImages.length,
        ),
      );
    }

    final coverPath = await _resolveCoverPath(directory, rootImages, chapters);
    if (coverPath == null) {
      return null;
    }

    final stat = await directory.stat();
    return LocalLibraryComic(
      folderId: folderId,
      title: titleOverride ?? p.basename(directory.path),
      path: directory.path,
      coverPath: coverPath,
      modifiedAt: stat.modified,
      chapters: chapters,
    );
  }

  Future<String?> _resolveCoverPath(
    Directory directory,
    List<File> rootImages,
    List<LocalLibraryChapter> chapters,
  ) async {
    for (final file in rootImages) {
      final name = p.basenameWithoutExtension(file.path).toLowerCase();
      if (name == 'cover') {
        return file.path;
      }
    }
    if (rootImages.isNotEmpty) {
      return rootImages.first.path;
    }
    if (chapters.isEmpty) {
      return null;
    }
    final firstChapter = Directory(chapters.first.path);
    final images = await _listImageFiles(firstChapter);
    if (images.isEmpty) {
      return null;
    }
    return images.first.path;
  }

  Future<List<File>> _listImageFiles(Directory directory) async {
    if (!await directory.exists()) {
      return const <File>[];
    }

    final images = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isImageFile(entity.path)) {
        images.add(entity);
      }
    }
    images.sort((a, b) => naturalComparePaths(a.path, b.path));
    return images;
  }

  bool _isImageFile(String path) {
    return _imageExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _isHiddenName(String path) {
    final name = p.basename(path);
    return name.startsWith('.');
  }

  String _displayNameForPath(String path) {
    final basename = p.basename(path);
    return basename.isEmpty ? path : basename;
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return p.normalize(Directory(trimmed).absolute.path);
  }

  bool _samePath(String a, String b) {
    return p.equals(_normalizePath(a), _normalizePath(b));
  }
}
