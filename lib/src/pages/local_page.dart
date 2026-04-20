import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../plugin_runtime/models.dart';
import '../state/app_state_controller.dart';
import 'comic_details_page.dart';
import 'local_reader_page.dart';
import 'network_resume_page.dart';

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
    if (restoredSection != null && restoredSection >= 0 && restoredSection <= 2) {
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
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        key: const PageStorageKey<String>('local-page-list'),
        padding: const EdgeInsets.all(24),
        children: [
          Text('Local', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 0, label: Text('History')),
              ButtonSegment<int>(value: 1, label: Text('Favorites')),
              ButtonSegment<int>(value: 2, label: Text('Downloads')),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (downloadController.jobs.isNotEmpty) ...[
          Text('Active Tasks', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          ...downloadController.jobs.map((job) => _DownloadJobCard(job: job)),
          const SizedBox(height: 20),
        ],
        Text('Downloaded Comics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (downloadController.downloads.isEmpty)
          const _LocalPlaceholder(
            title: 'No downloads yet',
            body: 'Use the detail page Download button to save comics locally.',
          )
        else
          ...downloadController.downloads.map(
            (comic) => _DownloadedComicCard(comic: comic),
          ),
      ],
    );
  }

  Widget _buildHistory(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (historyController.entries.isEmpty)
          const _LocalPlaceholder(
            title: 'No history yet',
            body: 'Open a chapter in the reader and it will appear here.',
          )
        else
          ...historyController.entries.map(
            (entry) => _HistoryCard(entry: entry),
          ),
      ],
    );
  }

  Widget _buildFavorites(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Favorites', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (favoriteController.entries.isEmpty)
          const _LocalPlaceholder(
            title: 'No favorites yet',
            body: 'Use the detail page Favorite button to add comics here.',
          )
        else
          ...favoriteController.entries.map(
            (entry) => _FavoriteCard(entry: entry),
          ),
      ],
    );
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
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

class _DownloadedComicCard extends StatelessWidget {
  const _DownloadedComicCard({required this.comic});

  final DownloadedComic comic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          comic.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((comic.subtitle ?? '').isNotEmpty) Text(comic.subtitle!),
              Text(
                '${comic.sourceKey} - ${comic.chapters.length} chapter(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'open') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => LocalReaderPage(comic: comic),
                ),
              );
            } else if (value == 'delete') {
              await DownloadController.instance.removeDownload(comic);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(value: 'open', child: Text('Open')),
            PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => LocalReaderPage(comic: comic),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final ReadingHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          entry.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((entry.subtitle ?? '').isNotEmpty) Text(entry.subtitle!),
              if ((entry.chapterTitle ?? '').isNotEmpty)
                Text(entry.chapterTitle!),
              Text(
                '${entry.sourceKey} - ${entry.timestamp}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        onTap: () => _openHistory(context),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    if (entry.isLocal) {
      final comic = DownloadController.instance.downloads
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
          builder: (context) => LocalReaderPage(comic: comic),
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
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.entry});

  final LocalFavoriteEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          entry.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((entry.subtitle ?? '').isNotEmpty) Text(entry.subtitle!),
              Text(
                entry.sourceKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await FavoriteController.instance.remove(entry);
          },
        ),
        onTap: () => _openFavorite(context),
      ),
    );
  }

  void _openFavorite(BuildContext context) {
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
