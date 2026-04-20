import 'package:flutter/material.dart';

import '../library/history_models.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import 'reader_page.dart';

class NetworkResumePage extends StatefulWidget {
  const NetworkResumePage({required this.entry, super.key});

  final ReadingHistoryEntry entry;

  @override
  State<NetworkResumePage> createState() => _NetworkResumePageState();
}

class _NetworkResumePageState extends State<NetworkResumePage> {
  late Future<_ResolvedReaderEntry> _future = _resolve();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedReaderEntry>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.entry.title)),
            body: const Center(
              child: SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.entry.title)),
            body: _ResumeError(
              message: snapshot.error?.toString() ?? 'Failed to restore reader.',
              onRetry: _retry,
            ),
          );
        }

        final resolved = snapshot.data!;
        return ReaderPage(
          sourceKey: widget.entry.sourceKey,
          comicId: widget.entry.comicId,
          comicTitle: resolved.title,
          chapterId: resolved.chapterId,
          chapterTitle: resolved.chapterTitle,
          chapters: resolved.chapters,
          subtitle: resolved.subtitle,
          cover: resolved.cover,
          initialPage: widget.entry.page,
        );
      },
    );
  }

  Future<_ResolvedReaderEntry> _resolve() async {
    final source = PluginRuntimeController.instance.find(widget.entry.sourceKey);
    final comicCapability = source?.comic;
    if (comicCapability == null) {
      throw StateError('Source does not support reading.');
    }

    final response = await comicCapability.loadInfo(widget.entry.comicId);
    if (response.isError) {
      throw StateError(response.errorMessage!);
    }

    final details = response.data;
    final selection = _resolveChapter(details.chapters);
    return _ResolvedReaderEntry(
      title: details.title.isEmpty ? widget.entry.title : details.title,
      subtitle: details.subtitle ?? widget.entry.subtitle,
      cover: details.cover.isEmpty ? widget.entry.cover : details.cover,
      chapters: details.chapters,
      chapterId: selection.$1,
      chapterTitle: selection.$2,
    );
  }

  (String?, String) _resolveChapter(PluginComicChapters? chapters) {
    if (chapters == null) {
      return (widget.entry.chapterId, widget.entry.chapterTitle ?? 'Read');
    }

    final flattened = <MapEntry<String, String>>[];
    if (chapters.isGrouped) {
      for (final group in chapters.groupedChapters!.values) {
        flattened.addAll(group.entries);
      }
    } else {
      flattened.addAll(chapters.chapters!.entries);
    }

    for (final entry in flattened) {
      if (entry.key == widget.entry.chapterId) {
        return (entry.key, entry.value);
      }
    }
    for (final entry in flattened) {
      if (entry.value == widget.entry.chapterTitle) {
        return (entry.key, entry.value);
      }
    }

    final first = flattened.firstOrNull;
    if (first == null) {
      return (widget.entry.chapterId, widget.entry.chapterTitle ?? 'Read');
    }
    return (first.key, first.value);
  }

  void _retry() {
    setState(() {
      _future = _resolve();
    });
  }
}

class _ResolvedReaderEntry {
  const _ResolvedReaderEntry({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.chapters,
    required this.chapterId,
    required this.chapterTitle,
  });

  final String title;
  final String? subtitle;
  final String? cover;
  final PluginComicChapters? chapters;
  final String? chapterId;
  final String chapterTitle;
}

class _ResumeError extends StatelessWidget {
  const _ResumeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
