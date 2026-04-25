import 'dart:io';

import 'package:flutter/material.dart';

import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../local_library/local_library_models.dart';
import '../utils/natural_sort.dart';

class LocalReaderPage extends StatefulWidget {
  const LocalReaderPage({
    required this.comic,
    this.initialChapterId,
    super.key,
  });

  final LocalLibraryComic comic;
  final String? initialChapterId;

  @override
  State<LocalReaderPage> createState() => _LocalReaderPageState();
}

class _LocalReaderPageState extends State<LocalReaderPage> {
  late LocalLibraryChapter selectedChapter = _resolveInitialChapter();

  @override
  void initState() {
    super.initState();
    _recordHistory(selectedChapter);
  }

  @override
  Widget build(BuildContext context) {
    final files = _chapterFiles(selectedChapter);

    return Scaffold(
      appBar: AppBar(title: Text(selectedChapter.title)),
      body: Column(
        children: [
          if (widget.comic.chapters.length > 1)
            SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final chapter = widget.comic.chapters[index];
                  return ChoiceChip(
                    label: Text(chapter.title),
                    selected: chapter.id == selectedChapter.id,
                    onSelected: (_) {
                      setState(() {
                        selectedChapter = chapter;
                      });
                      _recordHistory(chapter);
                    },
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemCount: widget.comic.chapters.length,
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      files[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 220,
                          alignment: Alignment.center,
                          child: const Text('Failed to load image'),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  LocalLibraryChapter _resolveInitialChapter() {
    if (widget.initialChapterId != null) {
      for (final chapter in widget.comic.chapters) {
        if (chapter.id == widget.initialChapterId) {
          return chapter;
        }
      }
    }
    return widget.comic.chapters.first;
  }

  List<File> _chapterFiles(LocalLibraryChapter chapter) {
    final directory = Directory(chapter.path);
    if (!directory.existsSync()) {
      return const <File>[];
    }

    final files = directory.listSync().whereType<File>().toList();
    files.sort((a, b) => naturalComparePaths(a.path, b.path));
    return files;
  }

  void _recordHistory(LocalLibraryChapter chapter) {
    HistoryController.instance.record(
      ReadingHistoryEntry(
        sourceKey: widget.comic.sourceKey,
        comicId: widget.comic.comicId,
        title: widget.comic.title,
        cover: widget.comic.coverPath,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        timestamp: DateTime.now(),
        isLocal: true,
        localComicPath: widget.comic.path,
        localFolderId: widget.comic.folderId,
      ),
    );
  }
}
