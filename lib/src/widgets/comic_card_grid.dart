import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import '../settings/settings_controller.dart';

/// Adaptive list/grid renderer for search & category results.
///
/// Switches between the default [ComicDisplayMode.grid] layout and the
/// venera-inspired [ComicDisplayMode.list] layout based on the current
/// [SettingsController.comicDisplayMode] preference.
class ComicDisplay extends StatelessWidget {
  const ComicDisplay({super.key, required this.comics, required this.onTap});

  final List<PluginComic> comics;
  final ValueChanged<PluginComic> onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsController.instance,
      builder: (context, _) {
        final mode = SettingsController.instance.comicDisplayMode;
        if (mode == ComicDisplayMode.list) {
          return ComicCardList(comics: comics, onTap: onTap);
        }
        return ComicCardGrid(comics: comics, onTap: onTap);
      },
    );
  }
}

class ComicCardGrid extends StatelessWidget {
  const ComicCardGrid({super.key, required this.comics, required this.onTap});

  final List<PluginComic> comics;
  final ValueChanged<PluginComic> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCountForWidth(constraints.maxWidth);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: comics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: switch (columns) {
              2 => 0.56,
              3 => 0.60,
              4 => 0.63,
              _ => 0.66,
            },
          ),
          itemBuilder: (context, index) {
            final comic = comics[index];
            return _ComicCard(comic: comic, onTap: () => onTap(comic));
          },
        );
      },
    );
  }

  int _columnCountForWidth(double width) {
    if (width >= 1440) {
      return 6;
    }
    if (width >= 1180) {
      return 5;
    }
    if (width >= 920) {
      return 4;
    }
    if (width >= 620) {
      return 3;
    }
    return 2;
  }
}

class ComicCardList extends StatelessWidget {
  const ComicCardList({super.key, required this.comics, required this.onTap});

  final List<PluginComic> comics;
  final ValueChanged<PluginComic> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comics.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final comic = comics[index];
        return _ComicListTile(comic: comic, onTap: () => onTap(comic));
      },
    );
  }
}

class _ComicCard extends StatefulWidget {
  const _ComicCard({required this.comic, required this.onTap});

  final PluginComic comic;
  final VoidCallback onTap;

  @override
  State<_ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<_ComicCard> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _subtitleText(widget.comic);
    final trailingMeta = _trailingMeta(widget.comic);
    final tags = widget.comic.tags
        ?.where((tag) => tag.trim().isNotEmpty)
        .toList();

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: isHovering ? 1.015 : 1,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isHovering
                      ? theme.colorScheme.primary.withValues(alpha: 0.32)
                      : theme.colorScheme.outlineVariant,
                ),
                boxShadow: [
                  if (isHovering)
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 10,
                    child: _ComicCover(
                      sourceKey: widget.comic.sourceKey,
                      imageUrl: widget.comic.cover,
                    ),
                  ),
                  Expanded(
                    flex: 8,
                    child: ClipRect(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                children: [
                                  _MetaPill(label: widget.comic.sourceKey),
                                  if (widget.comic.language case final language?
                                      when language.trim().isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    _MetaPill(label: language),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.comic.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
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
                              softWrap: true,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            const Spacer(),
                            if (tags != null && tags.isNotEmpty)
                              Text(
                                tags.take(3).join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              Text(
                                trailingMeta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleText(PluginComic comic) {
    final subtitle = comic.subtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) {
      return subtitle;
    }

    final description = comic.description.trim();
    if (description.isNotEmpty) {
      return description;
    }

    return comic.id;
  }

  String _trailingMeta(PluginComic comic) {
    if (comic.stars case final stars?) {
      return '★ ${stars.toStringAsFixed(1)}';
    }
    if (comic.maxPage case final maxPage?) {
      return '$maxPage pages';
    }
    return comic.id;
  }
}

/// List variant inspired by the venera detailed comic tile. Left cover,
/// right-hand metadata with compact tag chips - better suited to narrow
/// (phone) viewports where grid cards cannot fit full titles.
class _ComicListTile extends StatefulWidget {
  const _ComicListTile({required this.comic, required this.onTap});

  final PluginComic comic;
  final VoidCallback onTap;

  @override
  State<_ComicListTile> createState() => _ComicListTileState();
}

class _ComicListTileState extends State<_ComicListTile> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comic = widget.comic;
    final subtitle = comic.subtitle?.trim();
    final description = comic.description.trim();
    final tags = (comic.tags ?? const <String>[])
        .where((tag) => tag.trim().isNotEmpty)
        .toList();

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isHovering
                    ? theme.colorScheme.primary.withValues(alpha: 0.32)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  height: 112,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _ComicCover(
                      sourceKey: comic.sourceKey,
                      imageUrl: comic.cover,
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comic.maxPage == null
                            ? comic.title.replaceAll('\n', ' ')
                            : '[${comic.maxPage}P]${comic.title.replaceAll('\n', ' ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (tags.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in tags.take(4))
                              _MiniTag(label: tag),
                          ],
                        )
                      else if (description.isNotEmpty)
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _MetaPill(label: comic.sourceKey),
                          if (comic.language case final language?
                              when language.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _MetaPill(label: language),
                          ],
                          const Spacer(),
                          if (comic.stars case final stars?)
                            Text(
                              '★ ${stars.toStringAsFixed(1)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      constraints: const BoxConstraints(maxWidth: 140),
      child: Text(
        label.split(':').last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _ComicCover extends StatefulWidget {
  const _ComicCover({
    required this.sourceKey,
    required this.imageUrl,
    this.compact = false,
  });

  final String sourceKey;
  final String imageUrl;

  /// Small-mode cover used for the list tile. Removes the outer rounded
  /// container so the parent can apply its own shape.
  final bool compact;

  @override
  State<_ComicCover> createState() => _ComicCoverState();
}

class _ComicCoverState extends State<_ComicCover> {
  static final Map<String, Future<Uint8List>> _thumbnailCache =
      <String, Future<Uint8List>>{};

  Future<Uint8List>? imageFuture;

  @override
  void initState() {
    super.initState();
    imageFuture = _loadImage();
  }

  @override
  void didUpdateWidget(covariant _ComicCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.sourceKey != widget.sourceKey) {
      imageFuture = _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      width: double.infinity,
      child: widget.imageUrl.trim().isEmpty
          ? const _CoverFallback(icon: Icons.image_not_supported_outlined)
          : FutureBuilder<Uint8List>(
              future: imageFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }

                if (snapshot.hasError) {
                  return Image.network(
                    widget.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const _CoverFallback(
                        icon: Icons.broken_image_outlined,
                      );
                    },
                  );
                }

                return const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                );
              },
            ),
    );

    if (widget.compact) {
      return child;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: child,
    );
  }

  Future<Uint8List> _loadImage() {
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        size: 38,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
