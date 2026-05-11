import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import 'reader_page.dart';

class ComicDetailsPage extends StatefulWidget {
  const ComicDetailsPage({required this.comic, super.key});

  final PluginComic comic;

  @override
  State<ComicDetailsPage> createState() => _ComicDetailsPageState();
}

class _ComicDetailsPageState extends State<ComicDetailsPage> {
  late Future<PluginComicDetails> _future;
  final favoriteController = FavoriteController.instance;

  @override
  void initState() {
    super.initState();
    favoriteController.addListener(_onFavoriteChanged);
    _future = _loadComicDetails();
  }

  @override
  void dispose() {
    favoriteController.removeListener(_onFavoriteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.comic.title)),
      body: FutureBuilder<PluginComicDetails>(
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
            return _ComicDetailsError(
              message: snapshot.error.toString(),
              onRetry: _retry,
            );
          }

          final details = snapshot.data;
          if (details == null) {
            return _ComicDetailsError(
              message: 'No detail data returned.',
              onRetry: _retry,
            );
          }

          return _ComicDetailsBody(
            summary: widget.comic,
            details: details,
            onRead: () => _openReader(_firstChapter(details), details),
            onDownload: () => _downloadComic(details),
            onFavorite: () => _toggleFavorite(details),
            isFavorite: favoriteController.contains(
              widget.comic.sourceKey,
              widget.comic.id,
            ),
            onChapterSelected: (chapter) => _openReader(chapter, details),
          );
        },
      ),
    );
  }

  Future<PluginComicDetails> _loadComicDetails() async {
    final source = PluginRuntimeController.instance.find(
      widget.comic.sourceKey,
    );
    final comicCapability = source?.comic;
    if (comicCapability == null) {
      throw StateError('Source does not support comic details.');
    }

    final response = await comicCapability.loadInfo(widget.comic.id);
    if (response.isError) {
      throw StateError(response.errorMessage!);
    }
    return response.data;
  }

  void _retry() {
    setState(() {
      _future = _loadComicDetails();
    });
  }

  _ChapterSelection _firstChapter(PluginComicDetails details) {
    final chapters = details.chapters;
    if (chapters == null) {
      return const _ChapterSelection(id: null, title: 'Read');
    }

    if (chapters.isGrouped) {
      final firstGroup = chapters.groupedChapters!.entries.first;
      final firstChapter = firstGroup.value.entries.first;
      return _ChapterSelection(id: firstChapter.key, title: firstChapter.value);
    }

    final firstChapter = chapters.chapters!.entries.first;
    return _ChapterSelection(id: firstChapter.key, title: firstChapter.value);
  }

  void _openReader(_ChapterSelection chapter, PluginComicDetails details) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderPage(
          sourceKey: widget.comic.sourceKey,
          comicId: widget.comic.id,
          comicTitle: details.title,
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          chapters: details.chapters,
          subtitle: details.subtitle ?? widget.comic.subtitle,
          cover: details.cover.isNotEmpty ? details.cover : widget.comic.cover,
        ),
      ),
    );
  }

  Future<void> _downloadComic(PluginComicDetails details) async {
    List<ChapterDownloadRequest>? requests;
    if (details.chapters != null) {
      requests = await _showDownloadOptions(details);
      if (requests == null) {
        return;
      }
    }

    try {
      await DownloadController.instance.startDownload(
        summary: widget.comic,
        details: details,
        chapters: requests,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download started for ${details.title}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleFavorite(PluginComicDetails details) async {
    final entry = LocalFavoriteEntry(
      sourceKey: widget.comic.sourceKey,
      comicId: widget.comic.id,
      title: details.title,
      subtitle: details.subtitle ?? widget.comic.subtitle,
      cover: details.cover.isNotEmpty ? details.cover : widget.comic.cover,
      description: details.description ?? widget.comic.description,
      tags: widget.comic.tags ?? const <String>[],
      createdAt: DateTime.now(),
    );
    await favoriteController.toggle(entry);
  }

  void _onFavoriteChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<ChapterDownloadRequest>?> _showDownloadOptions(
    PluginComicDetails details,
  ) {
    final chapters = <ChapterDownloadRequest>[];
    if (details.chapters!.isGrouped) {
      for (final group in details.chapters!.groupedChapters!.values) {
        for (final entry in group.entries) {
          chapters.add(
            ChapterDownloadRequest(id: entry.key, title: entry.value),
          );
        }
      }
    } else {
      for (final entry in details.chapters!.chapters!.entries) {
        chapters.add(ChapterDownloadRequest(id: entry.key, title: entry.value));
      }
    }

    return showModalBottomSheet<List<ChapterDownloadRequest>>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Download All Chapters'),
                leading: const Icon(Icons.download_done_outlined),
                onTap: () => Navigator.of(context).pop(chapters),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    return ListTile(
                      title: Text(chapter.title),
                      subtitle: Text(chapter.id ?? 'main'),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(<ChapterDownloadRequest>[chapter]),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ComicDetailsBody extends StatelessWidget {
  const _ComicDetailsBody({
    required this.summary,
    required this.details,
    required this.onRead,
    required this.onDownload,
    required this.onFavorite,
    required this.isFavorite,
    required this.onChapterSelected,
  });

  final PluginComic summary;
  final PluginComicDetails details;
  final VoidCallback onRead;
  final VoidCallback onDownload;
  final VoidCallback onFavorite;
  final bool isFavorite;
  final ValueChanged<_ChapterSelection> onChapterSelected;

  /// Desktop <-> mobile breakpoint. Matches venera's `changePoint` so narrow
  /// desktop windows and phones share the same compact layout.
  static const double _mobileBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 0 : 24,
            vertical: isMobile ? 0 : 24,
          ),
          children: [
            const SizedBox(height: 8),
            _HeaderRow(
              summary: summary,
              details: details,
              isMobile: isMobile,
            ),
            const SizedBox(height: 16),
            _ActionStrip(
              isMobile: isMobile,
              isFavorite: isFavorite,
              onRead: onRead,
              onDownload: onDownload,
              onFavorite: onFavorite,
            ),
            const Divider(height: 24),
            if ((details.description ?? summary.description).trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Description',
                  child: Text(
                    details.description ?? summary.description,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(height: 1.6),
                  ),
                ),
              ),
            if (details.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Tags',
                  child: _TagsBlock(tags: details.tags),
                ),
              ),
            ],
            if (details.chapters != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Chapters',
                  child: _ChaptersView(
                    chapters: details.chapters!,
                    onChapterSelected: onChapterSelected,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

/// Compact cover + title row used on both mobile and desktop.
///
/// Inspired by venera's `buildTitle`: the cover stays at a fixed
/// portrait-friendly size (144h × 104w) so the text column gets all the
/// remaining width and the title wraps naturally on phones.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.summary,
    required this.details,
    required this.isMobile,
  });

  final PluginComic summary;
  final PluginComicDetails details;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = (details.subtitle ?? summary.subtitle ?? '').trim();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverCard(
            sourceKey: summary.sourceKey,
            imageUrl: details.cover.isNotEmpty ? details.cover : summary.cover,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  details.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  details.sourceKey,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (details.maxPage case final maxPage?) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$maxPage pages',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Venera-inspired action bar.
///
/// Desktop / wide: a single row of colored icon buttons (Read, Download,
/// Favorite) laid out horizontally.
///
/// Mobile / narrow: the horizontal icon strip stays compact (icons are
/// horizontally scrollable if needed), and two full-width primary actions
/// - Download and Read - are stacked beneath it for thumb reach.
class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.isMobile,
    required this.isFavorite,
    required this.onRead,
    required this.onDownload,
    required this.onFavorite,
  });

  final bool isMobile;
  final bool isFavorite;
  final VoidCallback onRead;
  final VoidCallback onDownload;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final iconRow = SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (!isMobile)
            _IconAction(
              icon: Icons.play_circle_outline,
              label: 'Read',
              color: Colors.orange,
              onPressed: onRead,
            ),
          if (!isMobile)
            _IconAction(
              icon: Icons.download_outlined,
              label: 'Download',
              color: Colors.cyan,
              onPressed: onDownload,
            ),
          _IconAction(
            icon: isFavorite ? Icons.bookmark : Icons.bookmark_outline,
            label: isFavorite ? 'Favorited' : 'Favorite',
            color: Colors.purple,
            active: isFavorite,
            onPressed: onFavorite,
          ),
        ],
      ),
    );

    if (!isMobile) {
      return iconRow;
    }

    return Column(
      children: [
        iconRow,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onDownload,
                  child: const Text('Download'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onRead,
                  child: const Text('Read'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = _contrastColor(theme, color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? effectiveColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ensures the decorative color stays readable on both light and dark
  /// themes without looking too bright.
  Color _contrastColor(ThemeData theme, Color base) {
    final hsl = HSLColor.fromColor(base);
    final isDark = theme.brightness == Brightness.dark;
    return hsl
        .withLightness(isDark ? 0.72 : 0.42)
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }
}

class _TagsBlock extends StatelessWidget {
  const _TagsBlock({required this.tags});

  final Map<String, List<String>> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tags.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.value
                    .map((tag) => Chip(label: Text(tag)))
                    .toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CoverCard extends StatefulWidget {
  const _CoverCard({required this.sourceKey, required this.imageUrl});

  final String sourceKey;
  final String imageUrl;

  @override
  State<_CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<_CoverCard> {
  static final Map<String, Future<Uint8List>> _thumbnailCache =
      <String, Future<Uint8List>>{};

  Future<Uint8List>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _CoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.sourceKey != widget.sourceKey) {
      _imageFuture = _loadThumbnail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 104,
      height: 144,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: widget.imageUrl.isEmpty
          ? Icon(
              Icons.image_not_supported_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 40,
            )
          : FutureBuilder<Uint8List>(
              future: _imageFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }
                if (snapshot.hasError) {
                  return Image.network(
                    widget.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 40,
                      );
                    },
                  );
                }
                return const Center(
                  child: SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                );
              },
            ),
    );
  }

  Future<Uint8List> _loadThumbnail() {
    final key = '${widget.sourceKey}|${widget.imageUrl}';
    return _thumbnailCache.putIfAbsent(key, () async {
      final source = PluginRuntimeController.instance.find(widget.sourceKey);
      if (source == null) {
        throw StateError('Missing source for thumbnail loading.');
      }
      return PluginImageLoader.instance.loadThumbnail(
        source: source,
        imageUrl: widget.imageUrl,
      );
    });
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ChaptersView extends StatelessWidget {
  const _ChaptersView({
    required this.chapters,
    required this.onChapterSelected,
  });

  final PluginComicChapters chapters;
  final ValueChanged<_ChapterSelection> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    if (chapters.isGrouped) {
      return Column(
        children: chapters.groupedChapters!.entries.map((entry) {
          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(entry.key),
            children: entry.value.entries.map((chapter) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(chapter.value),
                subtitle: Text(chapter.key),
                onTap: () {
                  onChapterSelected(
                    _ChapterSelection(id: chapter.key, title: chapter.value),
                  );
                },
              );
            }).toList(),
          );
        }).toList(),
      );
    }

    return Column(
      children: chapters.chapters!.entries.map((entry) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(entry.value),
          subtitle: Text(entry.key),
          onTap: () {
            onChapterSelected(
              _ChapterSelection(id: entry.key, title: entry.value),
            );
          },
        );
      }).toList(),
    );
  }
}

class _ChapterSelection {
  const _ChapterSelection({required this.id, required this.title});

  final String? id;
  final String title;
}

class _ComicDetailsError extends StatelessWidget {
  const _ComicDetailsError({required this.message, required this.onRetry});

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
                'Failed to load comic details',
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
