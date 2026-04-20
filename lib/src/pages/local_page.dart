import 'dart:io';

import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../localization/app_localizations.dart';
import '../plugin_runtime/models.dart';
import '../state/app_state_controller.dart';
import 'comic_details_page.dart';
import 'network_resume_page.dart';
import 'reader_page.dart';

class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  final downloadController = DownloadController.instance;
  final historyController = HistoryController.instance;
  final favoriteController = FavoriteController.instance;
  final appState = AppStateController.instance;

  late int selectedSection;

  @override
  void initState() {
    super.initState();
    final restoredSection = appState.getInt('local.selectedSection');
    if (restoredSection != null &&
        restoredSection >= 0 &&
        restoredSection <= 2) {
      selectedSection = restoredSection;
    } else {
      selectedSection = 2;
    }
    downloadController.addListener(_onChanged);
    historyController.addListener(_onChanged);
    favoriteController.addListener(_onChanged);
    downloadController.initialize();
    historyController.initialize();
    favoriteController.initialize();
  }

  @override
  void dispose() {
    downloadController.removeListener(_onChanged);
    historyController.removeListener(_onChanged);
    favoriteController.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: ListView(
        key: const PageStorageKey<String>('local-page-list'),
        padding: const EdgeInsets.all(24),
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(value: 0, label: Text(l10n.localHistory)),
              ButtonSegment<int>(value: 1, label: Text(l10n.localFavorites)),
              ButtonSegment<int>(value: 2, label: Text(l10n.localDownloads)),
            ],
            selected: <int>{selectedSection},
            onSelectionChanged: (values) {
              setState(() {
                selectedSection = values.first;
              });
              appState.setInt('local.selectedSection', selectedSection);
            },
          ),
          const SizedBox(height: 20),
          if (selectedSection == 2)
            _buildDownloads(context)
          else if (selectedSection == 0)
            _buildHistory(context)
          else
            _buildFavorites(context),
        ],
      ),
    );
  }

  Widget _buildDownloads(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (downloadController.jobs.isNotEmpty) ...[
          Text(l10n.localActiveTasks, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          ...downloadController.jobs.map((job) => _DownloadJobCard(job: job)),
          const SizedBox(height: 20),
        ],
        Text(l10n.localDownloadedComics, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (downloadController.downloads.isEmpty)
          _LocalPlaceholder(
            title: l10n.localNoDownloads,
            body: l10n.localNoDownloadsBody,
          )
        else
          _LocalComicGrid<DownloadedComic>(
            items: downloadController.downloads,
            itemBuilder: (context, comic) {
              return _LocalComicCard(
                title: comic.title,
                subtitle: comic.subtitle ?? comic.description ?? comic.comicId,
                meta: '${comic.chapters.length} chapter(s)',
                accent: comic.sourceKey,
                coverPath: comic.coverPath,
                onTap: () => _openDownloadedReader(context, comic),
                topRight: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) async {
                    if (value == 'open') {
                      _openDownloadedReader(context, comic);
                    } else if (value == 'delete') {
                      await DownloadController.instance.removeDownload(comic);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'open',
                      child: Text(l10n.open),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(l10n.delete),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHistory(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.localHistory, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (historyController.entries.isEmpty)
          _LocalPlaceholder(
            title: l10n.localNoHistory,
            body: l10n.localNoHistoryBody,
          )
        else
          _LocalComicGrid<ReadingHistoryEntry>(
            items: historyController.entries,
            itemBuilder: (context, entry) {
              return _LocalComicCard(
                title: entry.title,
                subtitle: (entry.chapterTitle ?? '').isNotEmpty
                    ? entry.chapterTitle!
                    : (entry.subtitle ?? entry.comicId),
                meta: _formatDateTime(entry.timestamp),
                accent: entry.sourceKey,
                coverPath: entry.isLocal ? entry.cover : null,
                coverUrl: entry.isLocal ? null : entry.cover,
                onTap: () => _openHistory(context, entry),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFavorites(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.localFavorites, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (favoriteController.entries.isEmpty)
          _LocalPlaceholder(
            title: l10n.localNoFavorites,
            body: l10n.localNoFavoritesBody,
          )
        else
          _LocalComicGrid<LocalFavoriteEntry>(
            items: favoriteController.entries,
            itemBuilder: (context, entry) {
              return _LocalComicCard(
                title: entry.title,
                subtitle: entry.subtitle ?? entry.description ?? entry.comicId,
                meta: entry.tags.isEmpty
                    ? l10n.localFavoriteMeta
                    : entry.tags.take(3).join(' | '),
                accent: entry.sourceKey,
                coverUrl: entry.cover,
                onTap: () => _openFavorite(context, entry),
                topRight: IconButton(
                  onPressed: () async {
                    await FavoriteController.instance.remove(entry);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              );
            },
          ),
      ],
    );
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openDownloadedReader(BuildContext context, DownloadedComic comic) {
    final firstTitle = comic.chapters.firstOrNull?.title ?? 'Read';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderPage(
          sourceKey: comic.sourceKey,
          comicId: comic.comicId,
          comicTitle: comic.title,
          chapterId: null,
          chapterTitle: firstTitle,
          subtitle: comic.subtitle,
          cover: comic.coverPath,
          localComic: comic,
        ),
      ),
    );
  }

  void _openHistory(BuildContext context, ReadingHistoryEntry entry) {
    if (entry.isLocal) {
      final comic = downloadController.downloads
          .where(
            (item) =>
                item.sourceKey == entry.sourceKey &&
                item.comicId == entry.comicId,
          )
          .firstOrNull;
      if (comic == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ReaderPage(
            sourceKey: comic.sourceKey,
            comicId: comic.comicId,
            comicTitle: comic.title,
            chapterId: entry.chapterId,
            chapterTitle: entry.chapterTitle ?? comic.chapters.first.title,
            subtitle: comic.subtitle,
            cover: comic.coverPath,
            initialPage: entry.page,
            localComic: comic,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NetworkResumePage(entry: entry),
      ),
    );
  }

  void _openFavorite(BuildContext context, LocalFavoriteEntry entry) {
    final comic = PluginComic(
      id: entry.comicId,
      title: entry.title,
      cover: entry.cover ?? '',
      sourceKey: entry.sourceKey,
      subtitle: entry.subtitle,
      tags: entry.tags,
      description: entry.description ?? '',
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComicDetailsPage(comic: comic),
      ),
    );
  }
}

class _DownloadJobCard extends StatelessWidget {
  const _DownloadJobCard({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(label: Text(job.status.name)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.progress == 0 ? null : job.progress,
            ),
            const SizedBox(height: 8),
            Text(
              job.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPlaceholder extends StatelessWidget {
  const _LocalPlaceholder({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalComicGrid<T> extends StatelessWidget {
  const _LocalComicGrid({required this.items, required this.itemBuilder});

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCountForWidth(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: columns == 2 ? 0.68 : 0.72,
          ),
          itemBuilder: (context, index) => itemBuilder(context, items[index]),
        );
      },
    );
  }

  int _columnCountForWidth(double width) {
    if (width >= 1380) {
      return 5;
    }
    if (width >= 1080) {
      return 4;
    }
    if (width >= 760) {
      return 3;
    }
    return 2;
  }
}

class _LocalComicCard extends StatelessWidget {
  const _LocalComicCard({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.accent,
    required this.onTap,
    this.coverPath,
    this.coverUrl,
    this.topRight,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String accent;
  final String? coverPath;
  final String? coverUrl;
  final VoidCallback onTap;
  final Widget? topRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 10,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _LocalComicCover(
                        coverPath: coverPath,
                        coverUrl: coverUrl,
                      ),
                    ),
                    if (topRight != null)
                      Positioned(top: 8, right: 8, child: topRight!),
                  ],
                ),
              ),
              Expanded(
                flex: 7,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          accent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalComicCover extends StatelessWidget {
  const _LocalComicCover({this.coverPath, this.coverUrl});

  final String? coverPath;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final filePath = coverPath?.trim();
    final networkUrl = coverUrl?.trim();

    Widget child;
    if (filePath != null &&
        filePath.isNotEmpty &&
        File(filePath).existsSync()) {
      child = Image.file(File(filePath), fit: BoxFit.cover);
    } else if (networkUrl != null && networkUrl.isNotEmpty) {
      child = Image.network(
        networkUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const _LocalCoverFallback();
        },
      );
    } else {
      child = const _LocalCoverFallback();
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _LocalCoverFallback extends StatelessWidget {
  const _LocalCoverFallback();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.menu_book_outlined,
        size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
