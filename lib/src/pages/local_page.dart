import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import 'local_reader_page.dart';

class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  final controller = DownloadController.instance;
  int selectedSection = 2;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    controller.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
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
            },
          ),
          const SizedBox(height: 20),
          if (selectedSection == 2)
            _buildDownloads(context)
          else if (selectedSection == 0)
            const _LocalPlaceholder(
              title: 'History is next',
              body:
                  'Download support lands first. History will be wired in a later step.',
            )
          else
            const _LocalPlaceholder(
              title: 'Favorites are next',
              body:
                  'Local favorites will be added after download and local reading stabilize.',
            ),
        ],
      ),
    );
  }

  Widget _buildDownloads(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.jobs.isNotEmpty) ...[
          Text('Active Tasks', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          ...controller.jobs.map((job) => _DownloadJobCard(job: job)),
          const SizedBox(height: 20),
        ],
        Text('Downloaded Comics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (controller.downloads.isEmpty)
          const _LocalPlaceholder(
            title: 'No downloads yet',
            body: 'Use the detail page Download button to save comics locally.',
          )
        else
          ...controller.downloads.map(
            (comic) => _DownloadedComicCard(comic: comic),
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
              if (!context.mounted) {
                return;
              }
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
