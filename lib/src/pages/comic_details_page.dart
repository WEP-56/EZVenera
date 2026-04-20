import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';

class ComicDetailsPage extends StatefulWidget {
  const ComicDetailsPage({required this.comic, super.key});

  final PluginComic comic;

  @override
  State<ComicDetailsPage> createState() => _ComicDetailsPageState();
}

class _ComicDetailsPageState extends State<ComicDetailsPage> {
  late Future<PluginComicDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadComicDetails();
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

          return _ComicDetailsBody(summary: widget.comic, details: details);
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
}

class _ComicDetailsBody extends StatelessWidget {
  const _ComicDetailsBody({required this.summary, required this.details});

  final PluginComic summary;
  final PluginComicDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverCard(
              imageUrl: details.cover.isNotEmpty
                  ? details.cover
                  : summary.cover,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((details.subtitle ?? summary.subtitle ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      details.subtitle ?? summary.subtitle!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(label: details.sourceKey),
                      _MetaChip(label: details.id),
                      if (details.maxPage case final maxPage?)
                        _MetaChip(label: '$maxPage pages'),
                      if (details.url case final url? when url.isNotEmpty)
                        _MetaChip(label: 'detail url'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _DisabledActionButton(label: 'Read'),
                      _DisabledActionButton(label: 'Download'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if ((details.description ?? summary.description).trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Description',
            child: Text(
              details.description ?? summary.description,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        ],
        if (details.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Tags',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details.tags.entries.map((entry) {
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
            ),
          ),
        ],
        if (details.chapters != null) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Chapters',
            child: _ChaptersView(chapters: details.chapters!),
          ),
        ],
      ],
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 156,
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: imageUrl.isEmpty
          ? Icon(
              Icons.image_not_supported_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 40,
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 40,
                );
              },
            ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _DisabledActionButton extends StatelessWidget {
  const _DisabledActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(onPressed: null, child: Text(label));
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
  const _ChaptersView({required this.chapters});

  final PluginComicChapters chapters;

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
        );
      }).toList(),
    );
  }
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
