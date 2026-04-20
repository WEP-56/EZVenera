import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import '../settings/settings_controller.dart';
import 'download_library_store.dart';
import 'download_models.dart';

class DownloadController extends ChangeNotifier {
  DownloadController._();

  static final DownloadController instance = DownloadController._();

  final DownloadLibraryStore _store = DownloadLibraryStore();
  final List<DownloadJob> _jobs = <DownloadJob>[];
  List<DownloadedComic> _downloads = const <DownloadedComic>[];
  bool _initialized = false;

  List<DownloadJob> get jobs => List<DownloadJob>.unmodifiable(_jobs);
  List<DownloadedComic> get downloads =>
      List<DownloadedComic>.unmodifiable(_downloads);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _store.initialize();
    _downloads = await _store.loadLibrary();
    _initialized = true;
    notifyListeners();
  }

  Future<String> getStoragePath() async {
    await _store.initialize();
    return _store.currentRootPath;
  }

  Future<void> startDownload({
    required PluginComic summary,
    required PluginComicDetails details,
    List<ChapterDownloadRequest>? chapters,
  }) async {
    await initialize();

    final source = PluginRuntimeController.instance.find(summary.sourceKey);
    if (source?.comic == null) {
      throw StateError('Source does not support download.');
    }

    final requests = chapters ?? _allChapterRequests(details);
    final job = DownloadJob(
      id: '${summary.sourceKey}@${summary.id}@${DateTime.now().millisecondsSinceEpoch}',
      title: details.title,
      sourceKey: summary.sourceKey,
      comicId: summary.id,
      totalUnits: requests.length,
      status: DownloadTaskStatus.queued,
      message: 'Queued',
    );

    _jobs.insert(0, job);
    notifyListeners();
    unawaited(_runJob(job, source!, summary, details, requests));
  }

  Future<void> removeDownload(DownloadedComic comic) async {
    await initialize();
    await _store.deleteComic(comic);
    _downloads = _downloads
        .where(
          (item) =>
              !(item.sourceKey == comic.sourceKey &&
                  item.comicId == comic.comicId),
        )
        .toList();
    await _store.saveLibrary(_downloads);
    notifyListeners();
  }

  Future<void> relocateLibrary(String? newRootPath) async {
    await initialize();
    final oldRootPath = await getStoragePath();

    await SettingsController.instance.setDownloadDirectoryPath(newRootPath);
    await _store.reloadConfiguration();
    final targetRootPath = _store.currentRootPath;
    if (p.equals(oldRootPath, targetRootPath)) {
      return;
    }

    final targetRoot = Directory(targetRootPath);
    await targetRoot.create(recursive: true);
    final relocated = <DownloadedComic>[];

    for (final comic in _downloads) {
      final sourceDirectory = Directory(comic.basePath);
      if (!await sourceDirectory.exists()) {
        relocated.add(comic);
        continue;
      }

      final destinationDirectory = await _createRelocatedComicDirectory(
        targetRoot,
        p.basename(comic.basePath),
      );
      await _copyDirectory(sourceDirectory, destinationDirectory);
      await sourceDirectory.delete(recursive: true);
      relocated.add(_relocateComic(comic, destinationDirectory.path));
    }

    _downloads = relocated;
    await _store.saveLibrary(_downloads);
    notifyListeners();
  }

  List<ChapterDownloadRequest> _allChapterRequests(PluginComicDetails details) {
    if (details.chapters == null) {
      return const <ChapterDownloadRequest>[
        ChapterDownloadRequest(id: null, title: 'Main'),
      ];
    }

    final requests = <ChapterDownloadRequest>[];
    if (details.chapters!.isGrouped) {
      for (final group in details.chapters!.groupedChapters!.values) {
        for (final entry in group.entries) {
          requests.add(
            ChapterDownloadRequest(id: entry.key, title: entry.value),
          );
        }
      }
    } else {
      for (final entry in details.chapters!.chapters!.entries) {
        requests.add(ChapterDownloadRequest(id: entry.key, title: entry.value));
      }
    }
    return requests;
  }

  Future<void> _runJob(
    DownloadJob job,
    PluginSource source,
    PluginComic summary,
    PluginComicDetails details,
    List<ChapterDownloadRequest> chapters,
  ) async {
    Directory? comicDirectory;

    try {
      job
        ..status = DownloadTaskStatus.running
        ..message = 'Preparing download';
      notifyListeners();

      comicDirectory = await _store.createComicDirectory(
        '${summary.sourceKey}_${details.title}',
      );

      final coverPath = await _saveCover(source, details, comicDirectory);
      final savedChapters = <DownloadedChapter>[];

      for (
        var chapterIndex = 0;
        chapterIndex < chapters.length;
        chapterIndex++
      ) {
        if (job.isCancelled) {
          throw _CancelledDownloadException();
        }

        final chapter = chapters[chapterIndex];
        job.message = 'Loading image list: ${chapter.title}';
        notifyListeners();

        final response = await source.comic!.loadEpisode(
          summary.id,
          chapter.id,
        );
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }

        final imageUrls = response.data;
        final chapterDirectory = await _createChapterDirectory(
          comicDirectory,
          details,
          chapter,
        );

        for (var imageIndex = 0; imageIndex < imageUrls.length; imageIndex++) {
          if (job.isCancelled) {
            throw _CancelledDownloadException();
          }

          job.message =
              'Downloading ${chapter.title} ${imageIndex + 1}/${imageUrls.length}';
          notifyListeners();

          final bytes = await PluginImageLoader.instance.loadComicImage(
            source: source,
            comicId: summary.id,
            episodeId: chapter.id ?? '0',
            imageUrl: imageUrls[imageIndex],
          );

          final extension = _guessExtension(imageUrls[imageIndex]);
          final path = p.join(
            chapterDirectory.path,
            '${imageIndex + 1}$extension',
          );
          await File(path).writeAsBytes(bytes);
        }

        savedChapters.add(
          DownloadedChapter(
            id: chapter.id ?? 'main',
            title: chapter.title,
            path: chapterDirectory.path,
            pageCount: imageUrls.length,
          ),
        );

        job.completedUnits = chapterIndex + 1;
        job.message = 'Downloaded ${chapter.title}';
        notifyListeners();
      }

      final comic = DownloadedComic(
        sourceKey: summary.sourceKey,
        comicId: summary.id,
        title: details.title,
        subtitle: details.subtitle ?? summary.subtitle,
        description: details.description ?? summary.description,
        coverPath: coverPath,
        tags: summary.tags ?? const <String>[],
        basePath: comicDirectory.path,
        createdAt: DateTime.now(),
        chapters: savedChapters,
      );

      _downloads = [
        comic,
        ..._downloads.where(
          (item) =>
              !(item.sourceKey == comic.sourceKey &&
                  item.comicId == comic.comicId),
        ),
      ];
      await _store.saveLibrary(_downloads);

      job
        ..status = DownloadTaskStatus.completed
        ..message = 'Completed';
      notifyListeners();
    } on _CancelledDownloadException {
      job
        ..status = DownloadTaskStatus.cancelled
        ..message = 'Cancelled';
      if (comicDirectory != null && await comicDirectory.exists()) {
        await comicDirectory.delete(recursive: true);
      }
      notifyListeners();
    } catch (error) {
      job
        ..status = DownloadTaskStatus.failed
        ..message = error.toString();
      if (comicDirectory != null && await comicDirectory.exists()) {
        await comicDirectory.delete(recursive: true);
      }
      notifyListeners();
    }
  }

  Future<Directory> _createChapterDirectory(
    Directory comicDirectory,
    PluginComicDetails details,
    ChapterDownloadRequest chapter,
  ) async {
    if (details.chapters == null) {
      return comicDirectory;
    }

    final directory = Directory(
      p.join(comicDirectory.path, _store.chapterDirectoryName(chapter.title)),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> _saveCover(
    PluginSource source,
    PluginComicDetails details,
    Directory comicDirectory,
  ) async {
    if (!SettingsController.instance.downloadSaveCover ||
        details.cover.isEmpty) {
      return null;
    }

    try {
      final bytes = await PluginImageLoader.instance.loadThumbnail(
        source: source,
        imageUrl: details.cover,
      );
      final extension = _guessExtension(details.cover);
      final path = p.join(comicDirectory.path, 'cover$extension');
      await File(path).writeAsBytes(bytes);
      return path;
    } catch (_) {
      return null;
    }
  }

  String _guessExtension(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri != null && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : url;
    final match = RegExp(
      r'\.(jpg|jpeg|png|webp|gif|bmp)$',
      caseSensitive: false,
    ).firstMatch(segment);
    if (match == null) {
      return '.jpg';
    }
    return '.${match.group(1)!.toLowerCase()}';
  }

  Future<Directory> _createRelocatedComicDirectory(
    Directory targetRoot,
    String preferredName,
  ) async {
    final sanitized = _store.sanitizeName(preferredName);
    var path = p.join(targetRoot.path, sanitized);
    var index = 1;
    while (await Directory(path).exists()) {
      path = p.join(targetRoot.path, '${sanitized}_$index');
      index++;
    }
    return Directory(path)..createSync(recursive: true);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(destination.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, name));
      }
    }
  }

  DownloadedComic _relocateComic(DownloadedComic comic, String newBasePath) {
    final newCoverPath = comic.coverPath == null
        ? null
        : p.join(newBasePath, p.basename(comic.coverPath!));
    final newChapters = comic.chapters.map((chapter) {
      final relocatedPath = p.equals(chapter.path, comic.basePath)
          ? newBasePath
          : p.join(newBasePath, p.basename(chapter.path));
      return DownloadedChapter(
        id: chapter.id,
        title: chapter.title,
        path: relocatedPath,
        pageCount: chapter.pageCount,
      );
    }).toList();

    return DownloadedComic(
      sourceKey: comic.sourceKey,
      comicId: comic.comicId,
      title: comic.title,
      subtitle: comic.subtitle,
      description: comic.description,
      coverPath: newCoverPath,
      tags: comic.tags,
      basePath: newBasePath,
      createdAt: comic.createdAt,
      chapters: newChapters,
    );
  }
}

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.title,
    required this.sourceKey,
    required this.comicId,
    required this.totalUnits,
    required this.status,
    required this.message,
  });

  final String id;
  final String title;
  final String sourceKey;
  final String comicId;
  final int totalUnits;
  DownloadTaskStatus status;
  String message;
  int completedUnits = 0;
  bool isCancelled = false;

  double get progress {
    if (totalUnits == 0) {
      return 0;
    }
    return completedUnits / totalUnits;
  }

  void cancel() {
    isCancelled = true;
  }
}

class _CancelledDownloadException implements Exception {}
