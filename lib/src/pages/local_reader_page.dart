import 'dart:io';

import 'package:flutter/material.dart';

import '../downloads/download_models.dart';

class LocalReaderPage extends StatefulWidget {
  const LocalReaderPage({required this.comic, super.key});

  final DownloadedComic comic;

  @override
  State<LocalReaderPage> createState() => _LocalReaderPageState();
}

class _LocalReaderPageState extends State<LocalReaderPage> {
  late DownloadedChapter selectedChapter = widget.comic.chapters.first;

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

  List<File> _chapterFiles(DownloadedChapter chapter) {
    final directory = Directory(chapter.path);
    if (!directory.existsSync()) {
      return const <File>[];
    }

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.contains('${Platform.pathSeparator}cover.'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }
}
