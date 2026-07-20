import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import '../reader/chapter_order.dart';
import 'categories_page.dart';
import 'category_comics_page.dart';
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
  final historyController = HistoryController.instance;
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  static const _backToTopThreshold = 420.0;

  @override
  void initState() {
    super.initState();
    favoriteController.addListener(_onFavoriteChanged);
    historyController.addListener(_onHistoryChanged);
    _scrollController.addListener(_onScrollChanged);
    _future = _loadComicDetails();
  }

  @override
  void dispose() {
    favoriteController.removeListener(_onFavoriteChanged);
    historyController.removeListener(_onHistoryChanged);
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
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
            _hideBackToTopAfterBuild();
            return const Center(
              child: SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          }

          if (snapshot.hasError) {
            _hideBackToTopAfterBuild();
            return _ComicDetailsError(
              message: snapshot.error.toString(),
              onRetry: _retry,
            );
          }

          final details = snapshot.data;
          if (details == null) {
            _hideBackToTopAfterBuild();
            return _ComicDetailsError(
              message: 'No detail data returned.',
              onRetry: _retry,
            );
          }

          final chaptersReversed = isChapterOrderReversedFor(
            widget.comic.sourceKey,
            widget.comic.id,
          );

          final hasHistory =
              HistoryController.instance.find(
                widget.comic.sourceKey,
                widget.comic.id,
              ) !=
              null;

          return _ComicDetailsBody(
            scrollController: _scrollController,
            summary: widget.comic,
            details: details,
            chaptersReversed: chaptersReversed,
            hasHistory: hasHistory,
            onRead: () => _openReader(
              _resolveReadChapter(details, chaptersReversed),
              details,
            ),
            onDownload: () => _downloadComic(details),
            onFavorite: () => _toggleFavorite(details),
            onToggleChapterOrder: () => _toggleChapterOrder(chaptersReversed),
            isFavorite: favoriteController.contains(
              widget.comic.sourceKey,
              widget.comic.id,
            ),
            onChapterSelected: (chapter) => _openReader(chapter, details),
            onPreviewPage: (page) => _openReaderAtPage(
              details,
              chaptersReversed,
              page,
            ),
            onTagTap: _onTagTap,
          );
        },
      ),
      floatingActionButton: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: _showBackToTop ? 1 : 0.86,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: _showBackToTop ? 1 : 0,
          child: IgnorePointer(
            ignoring: !_showBackToTop,
            child: FloatingActionButton.small(
              onPressed: _scrollToTop,
              shape: const CircleBorder(),
              child: const Icon(Icons.home_outlined),
            ),
          ),
        ),
      ),
    );
  }

  void _onScrollChanged() {
    final next =
        _scrollController.hasClients &&
        _scrollController.offset > _backToTopThreshold;
    if (next == _showBackToTop) {
      return;
    }
    setState(() {
      _showBackToTop = next;
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _hideBackToTopAfterBuild() {
    if (!_showBackToTop) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _showBackToTop = false;
        });
      }
    });
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

  _ChapterSelection _firstChapter(
    PluginComicDetails details,
    bool chaptersReversed,
  ) {
    final chapters = details.chapters;
    if (chapters == null) {
      return const _ChapterSelection(id: null, title: 'Read');
    }

    if (chapters.isGrouped) {
      final firstGroup = orderedChapterGroups(
        chapters.groupedChapters!,
        chaptersReversed,
      ).first;
      final firstChapter = orderedChapterEntries(
        firstGroup.value,
        chaptersReversed,
      ).first;
      return _ChapterSelection(id: firstChapter.key, title: firstChapter.value);
    }

    final firstChapter = orderedChapterEntries(
      chapters.chapters!,
      chaptersReversed,
    ).first;
    return _ChapterSelection(id: firstChapter.key, title: firstChapter.value);
  }

  /// Prefer the last reading position when the user taps Read/Continue.
  ///
  /// Previously Read always opened the first chapter. That both ignored
  /// progress and immediately overwrote history once the reader loaded.
  _ChapterSelection _resolveReadChapter(
    PluginComicDetails details,
    bool chaptersReversed,
  ) {
    final history = HistoryController.instance.find(
      widget.comic.sourceKey,
      widget.comic.id,
    );
    final fromHistory = _chapterFromHistory(details, history);
    return fromHistory ?? _firstChapter(details, chaptersReversed);
  }

  _ChapterSelection? _chapterFromHistory(
    PluginComicDetails details,
    ReadingHistoryEntry? history,
  ) {
    if (history == null) {
      return null;
    }

    final chapters = details.chapters;
    if (chapters == null) {
      if (history.chapterId == null && history.chapterTitle == null) {
        return null;
      }
      return _ChapterSelection(
        id: history.chapterId,
        title: history.chapterTitle ?? 'Read',
      );
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
      if (history.chapterId != null && entry.key == history.chapterId) {
        return _ChapterSelection(id: entry.key, title: entry.value);
      }
    }
    for (final entry in flattened) {
      if (history.chapterTitle != null && entry.value == history.chapterTitle) {
        return _ChapterSelection(id: entry.key, title: entry.value);
      }
    }
    return null;
  }

  void _openReader(
    _ChapterSelection chapter,
    PluginComicDetails details, {
    int? initialPage,
  }) {
    final history = HistoryController.instance.find(
      widget.comic.sourceKey,
      widget.comic.id,
    );
    // Resume page only when opening the same chapter as the saved progress.
    // Selecting a different chapter from the list starts at page 1.
    // Explicit [initialPage] (e.g. preview grid) always wins.
    final resumePage =
        initialPage ??
        (history != null &&
                history.chapterId != null &&
                history.chapterId == chapter.id
            ? history.page
            : null);

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
          initialPage: resumePage,
        ),
      ),
    );
  }

  /// Preview thumbnail tap — open first chapter (or no-chapter comic) at [page]
  /// (1-based), matching upstream `read(null, index + 1)`.
  void _openReaderAtPage(
    PluginComicDetails details,
    bool chaptersReversed,
    int page,
  ) {
    final chapter = _firstChapter(details, chaptersReversed);
    _openReader(chapter, details, initialPage: page);
  }

  /// Tag click is **source-scoped** via plugin `comic.onClickTag`, not aggregate
  /// search. Upstream: `comicSource.handleClickTagEvent?.call(namespace, tag)`.
  void _onTagTap(String namespace, String tag) {
    final source = PluginRuntimeController.instance.find(
      widget.comic.sourceKey,
    );
    final handler = source?.comic?.onClickTag;
    if (source == null || handler == null) {
      _showMessage('This source does not support tag search.');
      return;
    }

    PluginJumpTarget? target;
    try {
      target = handler(namespace, tag);
    } catch (error) {
      _showMessage(error.toString());
      return;
    }
    if (target == null || target.page == 'unknown') {
      return;
    }
    _openJumpTarget(source, target);
  }

  void _openJumpTarget(PluginSource source, PluginJumpTarget target) {
    if (target.page == 'category') {
      if (source.categoryComics == null) {
        _showMessage('This source does not support categories.');
        return;
      }
      final category =
          target.attributes?['category']?.toString() ??
          target.attributes?['keyword']?.toString() ??
          '';
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CategoryComicsPage(
            source: source,
            pageTitle: category.isEmpty ? source.name : category,
            categoryName: category,
            categoryParam: target.attributes?['param']?.toString(),
          ),
        ),
      );
      return;
    }

    if (target.page == 'search') {
      if (source.search == null) {
        _showMessage('This source does not support search.');
        return;
      }
      final optionsRaw = target.attributes?['options'];
      final options = optionsRaw is List
          ? optionsRaw.map((e) => e.toString()).toList()
          : const <String>[];
      final keyword =
          target.attributes?['keyword']?.toString() ??
          target.attributes?['text']?.toString() ??
          '';
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CategoryComicsSearchBridgePage(
            source: source,
            keyword: keyword,
            options: options,
          ),
        ),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _toggleChapterOrder(bool currentlyReversed) async {
    await setChapterOrderReversedFor(
      widget.comic.sourceKey,
      widget.comic.id,
      !currentlyReversed,
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _onFavoriteChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onHistoryChanged() {
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
    required this.scrollController,
    required this.summary,
    required this.details,
    required this.chaptersReversed,
    required this.hasHistory,
    required this.onRead,
    required this.onDownload,
    required this.onFavorite,
    required this.onToggleChapterOrder,
    required this.isFavorite,
    required this.onChapterSelected,
    required this.onPreviewPage,
    required this.onTagTap,
  });

  final ScrollController scrollController;
  final PluginComic summary;
  final PluginComicDetails details;
  final bool chaptersReversed;
  final bool hasHistory;
  final VoidCallback onRead;
  final VoidCallback onDownload;
  final VoidCallback onFavorite;
  final VoidCallback onToggleChapterOrder;
  final bool isFavorite;
  final ValueChanged<_ChapterSelection> onChapterSelected;
  final ValueChanged<int> onPreviewPage;
  final void Function(String namespace, String tag) onTagTap;

  /// Desktop <-> mobile breakpoint. Matches venera's `changePoint` so narrow
  /// desktop windows and phones share the same compact layout.
  static const double _mobileBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final description = (details.description ?? summary.description).trim();
    final source = PluginRuntimeController.instance.find(summary.sourceKey);
    final showPreview =
        (details.thumbnails != null && details.thumbnails!.isNotEmpty) ||
        source?.comic?.loadThumbnails != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 0 : 24,
            vertical: isMobile ? 0 : 24,
          ),
          children: [
            const SizedBox(height: 8),
            _HeaderRow(summary: summary, details: details, isMobile: isMobile),
            const SizedBox(height: 16),
            _ActionStrip(
              isMobile: isMobile,
              isFavorite: isFavorite,
              hasHistory: hasHistory,
              onRead: onRead,
              onDownload: onDownload,
              onFavorite: onFavorite,
            ),
            const Divider(height: 24),
            if (description.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Description',
                  child: GestureDetector(
                    onLongPress: () =>
                        _copyToClipboard(context, description, 'Description'),
                    child: Text(
                      description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ),
            if (details.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Tags',
                  child: _TagsBlock(
                    tags: details.tags,
                    canSearchTags: source?.comic?.onClickTag != null,
                    onTagTap: onTagTap,
                  ),
                ),
              ),
            ],
            if (showPreview) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Preview',
                  child: _PreviewGrid(
                    sourceKey: summary.sourceKey,
                    comicId: details.id,
                    initialThumbnails: details.thumbnails ?? const <String>[],
                    loadMore: source?.comic?.loadThumbnails,
                    onTapPage: onPreviewPage,
                  ),
                ),
              ),
            ],
            if (details.chapters != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
                child: _SectionCard(
                  title: 'Chapters',
                  trailing: TextButton.icon(
                    onPressed: onToggleChapterOrder,
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: Text(chaptersReversed ? 'Original' : 'Reverse'),
                  ),
                  child: _ChaptersView(
                    chapters: details.chapters!,
                    reversed: chaptersReversed,
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
                GestureDetector(
                  onLongPress: () =>
                      _copyToClipboard(context, details.title, 'Title'),
                  child: Text(
                    details.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onLongPress: () =>
                        _copyToClipboard(context, subtitle, 'Subtitle'),
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
    required this.hasHistory,
    required this.onRead,
    required this.onDownload,
    required this.onFavorite,
  });

  final bool isMobile;
  final bool isFavorite;
  final bool hasHistory;
  final VoidCallback onRead;
  final VoidCallback onDownload;
  final VoidCallback onFavorite;

  String get _readLabel => hasHistory ? 'Continue' : 'Read';

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
              label: _readLabel,
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
                  child: Text(_readLabel),
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
  const _TagsBlock({
    required this.tags,
    required this.canSearchTags,
    required this.onTagTap,
  });

  final Map<String, List<String>> tags;
  final bool canSearchTags;
  final void Function(String namespace, String tag) onTagTap;

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
                children: entry.value.map((tag) {
                  return Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.72,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: canSearchTags
                          ? () => onTagTap(entry.key, tag)
                          : null,
                      onLongPress: () => _copyToClipboard(context, tag, 'Tag'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          tag,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: canSearchTags
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Gallery thumbnail preview under description/tags (upstream `_ComicThumbnails`).
class _PreviewGrid extends StatefulWidget {
  const _PreviewGrid({
    required this.sourceKey,
    required this.comicId,
    required this.initialThumbnails,
    required this.loadMore,
    required this.onTapPage,
  });

  final String sourceKey;
  final String comicId;
  final List<String> initialThumbnails;
  final PluginThumbnailPageLoader? loadMore;
  final ValueChanged<int> onTapPage;

  @override
  State<_PreviewGrid> createState() => _PreviewGridState();
}

class _PreviewGridState extends State<_PreviewGrid> {
  late List<String> _thumbnails;
  String? _next;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _thumbnails = List<String>.from(widget.initialThumbnails);
    // Load first page of loadThumbnails when the details payload has none yet.
    if (_thumbnails.isEmpty && widget.loadMore != null) {
      _loadNext();
    } else {
      _initialLoadDone = true;
    }
  }

  Future<void> _loadNext() async {
    final loader = widget.loadMore;
    if (loader == null || _loading) {
      return;
    }
    if (_initialLoadDone && _next == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final response = await loader(widget.comicId, _next);
    if (!mounted) {
      return;
    }
    if (response.isError) {
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _error = response.errorMessage;
      });
      return;
    }
    setState(() {
      _thumbnails = [..._thumbnails, ...response.data];
      _next = response.subData?.toString();
      _loading = false;
      _initialLoadDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_thumbnails.isEmpty && _loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (_thumbnails.isEmpty && _error != null) {
      return Column(
        children: [
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          TextButton(onPressed: _loadNext, child: const Text('Retry')),
        ],
      );
    }

    if (_thumbnails.isEmpty) {
      return Text(
        'No previews available.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _thumbnails.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, index) {
            if (index == _thumbnails.length - 1 &&
                _error == null &&
                widget.loadMore != null) {
              // Trigger pagination when the last visible cell builds.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _loadNext();
                }
              });
            }
            final raw = _thumbnails[index];
            final url = _thumbnailDisplayUrl(raw);
            return _PreviewThumb(
              sourceKey: widget.sourceKey,
              imageUrl: url,
              pageLabel: '${index + 1}',
              onTap: () => widget.onTapPage(index + 1),
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          TextButton(onPressed: _loadNext, child: const Text('Retry')),
        ] else if (_loading) ...[
          const SizedBox(height: 12),
          const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        ],
      ],
    );
  }

  /// Strip crop fragment (`url@x=..&y=..`) — load the full image URL.
  String _thumbnailDisplayUrl(String raw) {
    final at = raw.indexOf('@');
    if (at <= 0) {
      return raw;
    }
    return raw.substring(0, at);
  }
}

class _PreviewThumb extends StatefulWidget {
  const _PreviewThumb({
    required this.sourceKey,
    required this.imageUrl,
    required this.pageLabel,
    required this.onTap,
  });

  final String sourceKey;
  final String imageUrl;
  final String pageLabel;
  final VoidCallback onTap;

  @override
  State<_PreviewThumb> createState() => _PreviewThumbState();
}

class _PreviewThumbState extends State<_PreviewThumb> {
  static final Map<String, Future<Uint8List>> _cache =
      <String, Future<Uint8List>>{};

  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _PreviewThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.sourceKey != widget.sourceKey) {
      _future = _load();
    }
  }

  Future<Uint8List> _load() {
    final key = '${widget.sourceKey}|${widget.imageUrl}';
    return _cache.putIfAbsent(key, () async {
      final source = PluginRuntimeController.instance.find(widget.sourceKey);
      if (source == null) {
        throw StateError('Missing source for preview thumbnail.');
      }
      return PluginImageLoader.instance.loadThumbnail(
        source: source,
        imageUrl: widget.imageUrl,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: FutureBuilder<Uint8List>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    );
                  }
                  if (snapshot.hasError) {
                    return Icon(
                      Icons.broken_image_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    );
                  }
                  return const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.pageLabel, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

void _copyToClipboard(BuildContext context, String text, [String? label]) {
  final value = text.trim();
  if (value.isEmpty) {
    return;
  }
  Clipboard.setData(ClipboardData(text: value));
  final message = label == null ? 'Copied' : '$label copied';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 1),
    ),
  );
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
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
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
    required this.reversed,
    required this.onChapterSelected,
  });

  final PluginComicChapters chapters;
  final bool reversed;
  final ValueChanged<_ChapterSelection> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    if (chapters.isGrouped) {
      return Column(
        children: orderedChapterGroups(chapters.groupedChapters!, reversed).map(
          (entry) {
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(entry.key),
              children: orderedChapterEntries(entry.value, reversed).map((
                chapter,
              ) {
                return _ChapterTile(
                  id: chapter.key,
                  title: chapter.value,
                  onTap: () {
                    onChapterSelected(
                      _ChapterSelection(id: chapter.key, title: chapter.value),
                    );
                  },
                );
              }).toList(),
            );
          },
        ).toList(),
      );
    }

    return Column(
      children: orderedChapterEntries(chapters.chapters!, reversed).map((
        entry,
      ) {
        return _ChapterTile(
          id: entry.key,
          title: entry.value,
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

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.id,
    required this.title,
    required this.onTap,
  });

  final String id;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(title),
          subtitle: Text(id),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
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
