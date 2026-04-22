import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../downloads/download_controller.dart';
import '../downloads/download_models.dart';
import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../local_library/local_library_controller.dart';
import '../local_library/local_library_models.dart';
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
  static const _desktopBreakpoint = 980.0;
  static const _selectionDownloads = 'downloads';
  static const _selectionHistory = 'history';
  static const _selectionFavorites = 'favorites';

  final downloadController = DownloadController.instance;
  final historyController = HistoryController.instance;
  final favoriteController = FavoriteController.instance;
  final localLibraryController = LocalLibraryController.instance;
  final appState = AppStateController.instance;

  late String selectedShelfKey;
  late bool sidebarCollapsed;

  @override
  void initState() {
    super.initState();
    selectedShelfKey = _restoreShelfKey();
    sidebarCollapsed = appState.getInt('local.sidebarCollapsed') == 1;
    downloadController.addListener(_onChanged);
    historyController.addListener(_onChanged);
    favoriteController.addListener(_onChanged);
    localLibraryController.addListener(_onChanged);
    downloadController.initialize();
    historyController.initialize();
    favoriteController.initialize();
    localLibraryController.initialize();
  }

  @override
  void dispose() {
    downloadController.removeListener(_onChanged);
    historyController.removeListener(_onChanged);
    favoriteController.removeListener(_onChanged);
    localLibraryController.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectionIsValid();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        final sidebar = _LocalSidebar(
          selectedShelfKey: selectedShelfKey,
          sidebarCollapsed: isDesktop ? sidebarCollapsed : false,
          historyCount: historyController.entries.length,
          favoriteCount: favoriteController.entries.length,
          downloadCount: downloadController.downloads.length,
          folders: localLibraryController.folders,
          folderCounts: {
            for (final folder in localLibraryController.folders)
              folder.id: localLibraryController.comicsFor(folder.id).length,
          },
          loadingFolderIds: {
            for (final folder in localLibraryController.folders)
              if (localLibraryController.isLoading(folder.id)) folder.id,
          },
          onSelectShelf: _selectShelf,
          onAddFolder: _addFolder,
          onOpenFolder: _openFolderEntry,
          onRemoveFolder: _removeFolderEntry,
          onRefreshFolder: _refreshFolderEntry,
          onToggleCollapse: isDesktop ? _toggleSidebar : null,
        );

        final content = _buildContent(context, isDesktop: isDesktop);

        if (isDesktop) {
          return SafeArea(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: sidebarCollapsed ? 88 : 292,
                  child: sidebar,
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return SafeArea(
          child: Column(
            children: [
              _buildMobileToolbar(context),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = _selectedMetadata(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _openFolderSheet,
            icon: const Icon(Icons.menu_open),
            tooltip: AppLocalizations.of(context).localFolderMenu,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metadata.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ..._buildHeaderActions(context),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, {required bool isDesktop}) {
    final metadata = _selectedMetadata(context);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          if (isDesktop) _buildDesktopHeader(context, metadata),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: SingleChildScrollView(
                key: ValueKey<String>(selectedShelfKey),
                padding: const EdgeInsets.all(24),
                child: _buildSelectedSection(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(BuildContext context, _SelectedMetadata metadata) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metadata.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ..._buildHeaderActions(context),
        ],
      ),
    );
  }

  List<Widget> _buildHeaderActions(BuildContext context) {
    final folder = _selectedFolder;
    final l10n = AppLocalizations.of(context);
    if (folder == null) {
      return const <Widget>[];
    }
    return [
      IconButton(
        onPressed: () => _refreshFolderEntry(folder),
        icon: const Icon(Icons.refresh),
        tooltip: l10n.localRefreshFolder,
      ),
      IconButton(
        onPressed: () => _openFolderEntry(folder),
        icon: const Icon(Icons.folder_open_outlined),
        tooltip: l10n.settingsOpenFolder,
      ),
      IconButton(
        onPressed: () => _removeFolderEntry(folder),
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.delete,
      ),
    ];
  }

  Widget _buildSelectedSection(BuildContext context) {
    return switch (selectedShelfKey) {
      _selectionDownloads => _buildDownloads(context),
      _selectionHistory => _buildHistory(context),
      _selectionFavorites => _buildFavorites(context),
      _ => _buildLocalFolder(context, _selectedFolder!),
    };
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
                meta: l10n.localChaptersPages(
                  comic.chapters.length,
                  comic.chapters.fold<int>(
                    0,
                    (total, chapter) => total + chapter.pageCount,
                  ),
                ),
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
                topRight: IconButton(
                  onPressed: () => historyController.remove(entry),
                  icon: const Icon(Icons.delete_outline),
                ),
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

  Widget _buildLocalFolder(BuildContext context, LocalComicFolderEntry folder) {
    final l10n = AppLocalizations.of(context);
    final error = localLibraryController.errorFor(folder.id);
    final loading = localLibraryController.isLoading(folder.id);
    final comics = localLibraryController.comicsFor(folder.id);

    if (loading && comics.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null && comics.isEmpty) {
      return _LocalPlaceholder(
        title: l10n.localFolderMissing,
        body: '$error\n\n${l10n.localFolderMissingBody}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        if (comics.isEmpty)
          _LocalPlaceholder(
            title: l10n.localNoFolderComics,
            body: l10n.localNoFolderComicsBody,
          )
        else
          _LocalComicGrid<LocalLibraryComic>(
            items: comics,
            itemBuilder: (context, comic) {
              return _LocalComicCard(
                title: comic.title,
                subtitle: pBasename(comic.path),
                meta: l10n.localChaptersPages(
                  comic.chapters.length,
                  comic.totalPages,
                ),
                accent: l10n.localLibraryBadge,
                coverPath: comic.coverPath,
                onTap: () => _openLocalComic(context, comic),
                topRight: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'open') {
                      _openLocalComic(context, comic);
                    } else if (value == 'folder') {
                      _openDirectory(comic.path);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'open',
                      child: Text(l10n.open),
                    ),
                    PopupMenuItem<String>(
                      value: 'folder',
                      child: Text(l10n.settingsOpenFolder),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  void _onChanged() {
    _ensureSelectionIsValid();
    if (mounted) {
      setState(() {});
    }
  }

  void _selectShelf(String shelfKey) {
    if (selectedShelfKey == shelfKey) {
      return;
    }
    setState(() {
      selectedShelfKey = shelfKey;
    });
    appState.setString('local.selectedShelf', shelfKey);
  }

  String _restoreShelfKey() {
    final restored = appState.getString('local.selectedShelf');
    if (restored != null && restored.isNotEmpty) {
      return restored;
    }

    final legacy = appState.getInt('local.selectedSection');
    return switch (legacy) {
      0 => _selectionHistory,
      1 => _selectionFavorites,
      _ => _selectionDownloads,
    };
  }

  LocalComicFolderEntry? get _selectedFolder {
    if (!selectedShelfKey.startsWith('folder:')) {
      return null;
    }
    return localLibraryController.folderById(
      selectedShelfKey.substring('folder:'.length),
    );
  }

  _SelectedMetadata _selectedMetadata(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (selectedShelfKey) {
      _selectionHistory => _SelectedMetadata(
        title: l10n.localHistory,
        subtitle: l10n.localComicsCount(historyController.entries.length),
      ),
      _selectionFavorites => _SelectedMetadata(
        title: l10n.localFavorites,
        subtitle: l10n.localComicsCount(favoriteController.entries.length),
      ),
      _selectionDownloads => _SelectedMetadata(
        title: l10n.localDownloads,
        subtitle: l10n.localComicsCount(downloadController.downloads.length),
      ),
      _ => _SelectedMetadata(
        title: _selectedFolder?.name ?? l10n.localLibrary,
        subtitle: _selectedFolder == null
            ? l10n.localNoFolders
            : localLibraryController.errorFor(_selectedFolder!.id) != null
            ? l10n.localFolderMissing
            : l10n.localComicsCount(
                localLibraryController.comicsFor(_selectedFolder!.id).length,
              ),
      ),
    };
  }

  Future<void> _addFolder() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) {
        return;
      }
      final folder = await localLibraryController.addFolder(selected);
      if (!mounted) {
        return;
      }
      _selectShelf('folder:${folder.id}');
      _showMessage(l10n.localFolderAdded);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(l10n.localFolderPickerFailed);
    }
  }

  Future<void> _refreshFolderEntry(LocalComicFolderEntry folder) async {
    await localLibraryController.refreshFolder(folder.id);
  }

  Future<void> _removeFolderEntry(LocalComicFolderEntry folder) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.localRemoveFolderTitle),
          content: Text(l10n.localRemoveFolderBody(folder.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await localLibraryController.removeFolder(folder.id);
    if (selectedShelfKey == 'folder:${folder.id}') {
      _selectShelf(_selectionDownloads);
    }
    if (mounted) {
      _showMessage(l10n.localFolderRemoved);
    }
  }

  Future<void> _openFolderEntry(LocalComicFolderEntry folder) {
    return _openDirectory(folder.path);
  }

  Future<void> _openDirectory(String path) async {
    final l10n = AppLocalizations.of(context);
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
        return;
      }
      final opened = await launchUrl(
        Uri.directory(path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('open failed');
      }
    } catch (_) {
      if (mounted) {
        _showMessage(l10n.settingsDirectoryOpenFailed);
      }
    }
  }

  void _openFolderSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: _LocalSidebar(
              selectedShelfKey: selectedShelfKey,
              sidebarCollapsed: false,
              historyCount: historyController.entries.length,
              favoriteCount: favoriteController.entries.length,
              downloadCount: downloadController.downloads.length,
              folders: localLibraryController.folders,
              folderCounts: {
                for (final folder in localLibraryController.folders)
                  folder.id: localLibraryController.comicsFor(folder.id).length,
              },
              loadingFolderIds: {
                for (final folder in localLibraryController.folders)
                  if (localLibraryController.isLoading(folder.id)) folder.id,
              },
              onSelectShelf: (value) {
                Navigator.of(context).pop();
                _selectShelf(value);
              },
              onAddFolder: () async {
                Navigator.of(context).pop();
                await _addFolder();
              },
              onOpenFolder: (folder) async {
                Navigator.of(context).pop();
                await _openFolderEntry(folder);
              },
              onRemoveFolder: (folder) async {
                Navigator.of(context).pop();
                await _removeFolderEntry(folder);
              },
              onRefreshFolder: (folder) async {
                Navigator.of(context).pop();
                await _refreshFolderEntry(folder);
              },
            ),
          ),
        );
      },
    );
  }

  void _toggleSidebar() {
    setState(() {
      sidebarCollapsed = !sidebarCollapsed;
    });
    appState.setInt('local.sidebarCollapsed', sidebarCollapsed ? 1 : 0);
  }

  void _ensureSelectionIsValid() {
    final folder = _selectedFolder;
    if (selectedShelfKey.startsWith('folder:') && folder == null) {
      selectedShelfKey = _selectionDownloads;
      appState.setString('local.selectedShelf', selectedShelfKey);
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

  Future<void> _openHistory(
    BuildContext context,
    ReadingHistoryEntry entry,
  ) async {
    if (entry.localComicPath != null) {
      final comic = await localLibraryController.scanComicPath(
        entry.localComicPath!,
        folderId: entry.localFolderId ?? 'history',
      );
      if (comic == null) {
        if (!context.mounted) {
          return;
        }
        _showMessage(AppLocalizations.of(context).localFolderMissing);
        return;
      }
      if (!context.mounted) {
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
            cover: comic.coverPath,
            initialPage: entry.page,
            localLibraryComic: comic,
          ),
        ),
      );
      return;
    }

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

  void _openLocalComic(BuildContext context, LocalLibraryComic comic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderPage(
          sourceKey: comic.sourceKey,
          comicId: comic.comicId,
          comicTitle: comic.title,
          chapterId: null,
          chapterTitle: comic.chapters.first.title,
          cover: comic.coverPath,
          localLibraryComic: comic,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LocalSidebar extends StatelessWidget {
  const _LocalSidebar({
    required this.selectedShelfKey,
    required this.sidebarCollapsed,
    required this.historyCount,
    required this.favoriteCount,
    required this.downloadCount,
    required this.folders,
    required this.folderCounts,
    required this.loadingFolderIds,
    required this.onSelectShelf,
    required this.onAddFolder,
    required this.onOpenFolder,
    required this.onRemoveFolder,
    required this.onRefreshFolder,
    this.onToggleCollapse,
  });

  final String selectedShelfKey;
  final bool sidebarCollapsed;
  final int historyCount;
  final int favoriteCount;
  final int downloadCount;
  final List<LocalComicFolderEntry> folders;
  final Map<String, int> folderCounts;
  final Set<String> loadingFolderIds;
  final ValueChanged<String> onSelectShelf;
  final Future<void> Function() onAddFolder;
  final Future<void> Function(LocalComicFolderEntry folder) onOpenFolder;
  final Future<void> Function(LocalComicFolderEntry folder) onRemoveFolder;
  final Future<void> Function(LocalComicFolderEntry folder) onRefreshFolder;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.95),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
            child: Row(
              children: [
                Icon(
                  Icons.folder_copy_outlined,
                  color: theme.colorScheme.primary,
                ),
                if (!sidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.localLibrary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (onToggleCollapse != null)
                  IconButton(
                    onPressed: onToggleCollapse,
                    icon: Icon(
                      sidebarCollapsed
                          ? Icons.chevron_right
                          : Icons.chevron_left,
                    ),
                    tooltip: sidebarCollapsed
                        ? l10n.localExpandSidebar
                        : l10n.localCollapseSidebar,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              children: [
                _SidebarSectionLabel(
                  title: l10n.localSystemFolders,
                  collapsed: sidebarCollapsed,
                ),
                _SidebarItem(
                  label: l10n.localHistory,
                  icon: Icons.history,
                  selected:
                      selectedShelfKey == _LocalPageState._selectionHistory,
                  count: historyCount,
                  collapsed: sidebarCollapsed,
                  onTap: () => onSelectShelf(_LocalPageState._selectionHistory),
                ),
                const SizedBox(height: 8),
                _SidebarItem(
                  label: l10n.localFavorites,
                  icon: Icons.favorite_border,
                  selected:
                      selectedShelfKey == _LocalPageState._selectionFavorites,
                  count: favoriteCount,
                  collapsed: sidebarCollapsed,
                  onTap: () =>
                      onSelectShelf(_LocalPageState._selectionFavorites),
                ),
                const SizedBox(height: 8),
                _SidebarItem(
                  label: l10n.localDownloads,
                  icon: Icons.download_outlined,
                  selected:
                      selectedShelfKey == _LocalPageState._selectionDownloads,
                  count: downloadCount,
                  collapsed: sidebarCollapsed,
                  onTap: () =>
                      onSelectShelf(_LocalPageState._selectionDownloads),
                ),
                const SizedBox(height: 18),
                _SidebarFolderHeader(
                  title: l10n.localFolders,
                  collapsed: sidebarCollapsed,
                  onAdd: onAddFolder,
                ),
                const SizedBox(height: 10),
                if (folders.isEmpty)
                  _SidebarEmptyHint(
                    title: l10n.localNoFolders,
                    body: l10n.localNoFoldersBody,
                    collapsed: sidebarCollapsed,
                  )
                else
                  for (final folder in folders) ...[
                    _SidebarItem(
                      label: folder.name,
                      icon: Icons.folder_outlined,
                      selected: selectedShelfKey == 'folder:${folder.id}',
                      count: folderCounts[folder.id] ?? 0,
                      collapsed: sidebarCollapsed,
                      trailing: sidebarCollapsed
                          ? null
                          : PopupMenuButton<String>(
                              icon: loadingFolderIds.contains(folder.id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.more_horiz),
                              onSelected: (value) async {
                                if (value == 'refresh') {
                                  await onRefreshFolder(folder);
                                } else if (value == 'open') {
                                  await onOpenFolder(folder);
                                } else if (value == 'delete') {
                                  await onRemoveFolder(folder);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'refresh',
                                  child: Text(l10n.localRefreshFolder),
                                ),
                                PopupMenuItem<String>(
                                  value: 'open',
                                  child: Text(l10n.settingsOpenFolder),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                      onTap: () => onSelectShelf('folder:${folder.id}'),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFolderHeader extends StatelessWidget {
  const _SidebarFolderHeader({
    required this.title,
    required this.collapsed,
    required this.onAdd,
  });

  final String title;
  final bool collapsed;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        if (!collapsed)
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          const Spacer(),
        IconButton(
          onPressed: onAdd,
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: AppLocalizations.of(context).localAddFolder,
        ),
      ],
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.title, required this.collapsed});

  final String title;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.count,
    required this.collapsed,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, color: foreground),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                trailing ??
                    _SidebarCountBadge(count: count, selected: selected),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarCountBadge extends StatelessWidget {
  const _SidebarCountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SidebarEmptyHint extends StatelessWidget {
  const _SidebarEmptyHint({
    required this.title,
    required this.body,
    required this.collapsed,
  });

  final String title;
  final String body;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedMetadata {
  const _SelectedMetadata({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
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

String pBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? path : segments.last;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
