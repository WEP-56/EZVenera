import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    required this.sourceKey,
    required this.comicId,
    required this.comicTitle,
    required this.chapterId,
    required this.chapterTitle,
    super.key,
  });

  final String sourceKey;
  final String comicId;
  final String comicTitle;
  final String? chapterId;
  final String chapterTitle;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late Future<List<String>> _future = _loadImages();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chapterTitle), centerTitle: false),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          }

          if (snapshot.hasError) {
            return _ReaderError(
              message: snapshot.error.toString(),
              onRetry: _retry,
            );
          }

          final images = snapshot.data;
          if (images == null || images.isEmpty) {
            return _ReaderError(
              message: 'No images returned for this chapter.',
              onRetry: _retry,
            );
          }

          return ListView.builder(
            itemCount: images.length,
            itemBuilder: (context, index) {
              return _ReaderImage(
                sourceKey: widget.sourceKey,
                comicId: widget.comicId,
                chapterId: widget.chapterId ?? '0',
                imageUrl: images[index],
                index: index + 1,
              );
            },
          );
        },
      ),
    );
  }

  Future<List<String>> _loadImages() async {
    final source = PluginRuntimeController.instance.find(widget.sourceKey);
    final comicCapability = source?.comic;
    if (comicCapability == null) {
      throw StateError('Source does not support reading.');
    }

    final response = await comicCapability.loadEpisode(
      widget.comicId,
      widget.chapterId,
    );
    if (response.isError) {
      throw StateError(response.errorMessage!);
    }
    return response.data;
  }

  void _retry() {
    setState(() {
      _future = _loadImages();
    });
  }
}

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({
    required this.sourceKey,
    required this.comicId,
    required this.chapterId,
    required this.imageUrl,
    required this.index,
  });

  final String sourceKey;
  final String comicId;
  final String chapterId;
  final String imageUrl;
  final int index;

  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  late Future<Uint8List> _future = _loadBytes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 220),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failed to load page ${widget.index}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List> _loadBytes() async {
    final source = PluginRuntimeController.instance.find(widget.sourceKey);
    if (source == null) {
      throw StateError('Source not found.');
    }

    return PluginImageLoader.instance.loadComicImage(
      source: source,
      comicId: widget.comicId,
      episodeId: widget.chapterId,
      imageUrl: widget.imageUrl,
    );
  }

  void _retry() {
    setState(() {
      _future = _loadBytes();
    });
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load chapter',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
