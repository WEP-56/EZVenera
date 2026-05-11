import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../downloads/download_models.dart';
import '../downloads/download_controller.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../local_library/local_library_models.dart';
import '../localization/app_localizations.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/result.dart';
import '../reader/reader_image_cache.dart';
import '../settings/settings_controller.dart';
import '../utils/natural_sort.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    required this.sourceKey,
    required this.comicId,
    required this.comicTitle,
    required this.chapterId,
    required this.chapterTitle,
    this.chapters,
    this.subtitle,
    this.cover,
    this.initialPage,
    this.localComic,
    this.localLibraryComic,
    super.key,
  });

  final String sourceKey;
  final String comicId;
  final String comicTitle;
  final String? chapterId;
  final String chapterTitle;
  final PluginComicChapters? chapters;
  final String? subtitle;
  final String? cover;
  final int? initialPage;
  final DownloadedComic? localComic;
  final LocalLibraryComic? localLibraryComic;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late String? currentChapterId;
  late String currentChapterTitle;
  late String currentComicTitle;
  late String? currentSubtitle;
  late String? currentCover;
  late PluginComicChapters? currentChapters;

  List<String> images = const <String>[];
  bool isLoading = true;
  String? error;
  int currentPage = 1;
  PageController? pageController;
  ReaderPageMode? _pageControllerMode;
  final FocusNode focusNode = FocusNode();
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  bool _attemptedContextLoad = false;
  bool _controlsVisible = false;
  bool _isCurrentImageZoomed = false;
  TapUpDetails? _pendingTapDetails;
  Timer? _pendingTapTimer;
  final Map<int, GlobalKey<_ReaderImageState>> _imageKeys =
      <int, GlobalKey<_ReaderImageState>>{};

  static const _doubleTapMaxDelay = Duration(milliseconds: 220);
  static const _doubleTapMaxDistanceSquared = 24.0 * 24.0;
  static const _tapToTurnPagePercent = 0.33;

  bool _isFullscreen = false;
  Timer? _autoPageTimer;

  bool get _isPureLocalReader =>
      widget.localComic != null || widget.localLibraryComic != null;

  @override
  void initState() {
    super.initState();
    SettingsController.instance.addListener(_onSettingsChanged);
    final history = HistoryController.instance.find(
      widget.sourceKey,
      widget.comicId,
    );
    currentChapterId = widget.chapterId ?? history?.chapterId;
    currentChapterTitle =
        widget.chapterId == null && history?.chapterTitle != null
        ? history!.chapterTitle!
        : widget.chapterTitle;
    currentComicTitle = widget.comicTitle;
    currentSubtitle = widget.subtitle ?? history?.subtitle;
    currentCover =
        widget.localComic?.coverPath ??
        widget.localLibraryComic?.coverPath ??
        widget.cover ??
        history?.cover;
    currentChapters = widget.chapters;

    final initialPage =
        widget.initialPage ??
        (widget.chapterId == null || history?.chapterId == currentChapterId
            ? (history?.page ?? 1)
            : 1);
    _loadChapter(
      initialPage: initialPage,
      preferContextLoad: widget.chapters == null,
    );
  }

  @override
  void dispose() {
    SettingsController.instance.removeListener(_onSettingsChanged);
    _pendingTapTimer?.cancel();
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (_isFullscreen) {
      _restoreFullscreenOnDispose();
    }
    focusNode.dispose();
    pageController?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    final newMode = SettingsController.instance.readerPageMode;
    if (_pageControllerMode != null && _pageControllerMode != newMode) {
      // PageView does not support changing scrollDirection in place; we must
      // recreate the controller so the new axis/reverse is picked up cleanly.
      final previousPage = currentPage;
      pageController?.dispose();
      pageController = PageController(initialPage: previousPage - 1);
      _pageControllerMode = newMode;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(toolbarHeight: 0),
      endDrawer: _ReaderSettingsDrawer(
        onClose: () => Navigator.of(context).maybePop(),
        tapToTurn: SettingsController.instance.readerEnableTapToTurnPages,
        reverseTapToTurn:
            SettingsController.instance.readerReverseTapToTurnPages,
        doubleTapZoom: SettingsController.instance.readerEnableDoubleTapZoom,
        pageAnimation: SettingsController.instance.readerEnablePageAnimation,
        autoPageIntervalSeconds:
            SettingsController.instance.readerAutoPageIntervalSeconds,
        pageMode: SettingsController.instance.readerPageMode,
        onPageModeChanged: (value) async {
          await SettingsController.instance.setReaderPageMode(value);
          if (mounted) {
            setState(() {});
          }
        },
        onTapToTurnChanged: (value) async {
          await SettingsController.instance.setReaderEnableTapToTurnPages(
            value,
          );
          if (mounted) {
            setState(() {});
          }
        },
        onReverseTapToTurnChanged: (value) async {
          await SettingsController.instance.setReaderReverseTapToTurnPages(
            value,
          );
          if (mounted) {
            setState(() {});
          }
        },
        onDoubleTapZoomChanged: (value) async {
          await SettingsController.instance.setReaderEnableDoubleTapZoom(value);
          if (mounted) {
            setState(() {});
          }
        },
        onPageAnimationChanged: (value) async {
          await SettingsController.instance.setReaderEnablePageAnimation(value);
          if (mounted) {
            setState(() {});
          }
        },
        onAutoPageIntervalChanged: (value) async {
          await SettingsController.instance.setReaderAutoPageIntervalSeconds(
            value,
          );
          if (_autoPageTimer != null) {
            _startAutoPage(showMessage: false);
          }
          if (mounted) {
            setState(() {});
          }
        },
      ),
      body: Focus(
        autofocus: true,
        focusNode: focusNode,
        onKeyEvent: _onKeyEvent,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (error != null) {
      return _ReaderError(
        message: error!,
        onRetry: () => _loadChapter(initialPage: currentPage),
      );
    }

    if (images.isEmpty || pageController == null) {
      return _ReaderError(
        message: 'No images returned for this chapter.',
        onRetry: () => _loadChapter(initialPage: currentPage),
      );
    }

    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) {
          return;
        }
        if (_isCurrentImageZoomed) {
          return;
        }
        if (signal.scrollDelta.dy > 0) {
          _goToNextPage();
        } else if (signal.scrollDelta.dy < 0) {
          _goToPreviousPage();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageMode = SettingsController.instance.readerPageMode;
          final isVertical =
              pageMode == ReaderPageMode.continuousTopToBottom;
          final isRtl = pageMode == ReaderPageMode.galleryRightToLeft;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, constraints.biggest),
            child: Stack(
              children: [
                PageView.builder(
                  key: ValueKey<ReaderPageMode>(pageMode),
                  controller: pageController,
                  itemCount: images.length,
                  scrollDirection:
                      isVertical ? Axis.vertical : Axis.horizontal,
                  reverse: isRtl,
                  physics: _isCurrentImageZoomed
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  onPageChanged: (index) {
                    currentPage = index + 1;
                    _isCurrentImageZoomed = false;
                    _recordHistory();
                    _prefetchAround(currentPage);
                    setState(() {});
                  },
                  itemBuilder: (context, index) {
                    return _ReaderImage(
                      key: _imageKeyFor(index),
                      isLocal:
                          widget.localComic != null ||
                          widget.localLibraryComic != null,
                      sourceKey: widget.sourceKey,
                      comicId: widget.comicId,
                      chapterId: currentChapterId ?? '0',
                      imageUrl: images[index],
                      index: index + 1,
                      isActive: index + 1 == currentPage,
                      onZoomChanged: (zoomed) {
                        if (!mounted || currentPage != index + 1) {
                          return;
                        }
                        if (_isCurrentImageZoomed != zoomed) {
                          setState(() {
                            _isCurrentImageZoomed = zoomed;
                          });
                        }
                      },
                    );
                  },
                ),
                if (SettingsController.instance.readerShowTapGuide &&
                    !_controlsVisible &&
                    !_isCurrentImageZoomed)
                  Positioned(
                    right: 16,
                    bottom: 18,
                    child: _ReaderTapGuide(
                      visible: !_controlsVisible && !_isCurrentImageZoomed,
                    ),
                  ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  top: _controlsVisible
                      ? 0
                      : -(72 + MediaQuery.paddingOf(context).top),
                  left: 0,
                  right: 0,
                  child: _ReaderTopBar(
                    title: currentComicTitle,
                    chapterTitle: currentChapterTitle,
                    showChapters: _chapterItems.isNotEmpty,
                    onBack: () => Navigator.of(context).maybePop(),
                    onOpenChapters: _showChapterSelector,
                    onOpenSettings: _openReaderSettings,
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  left: 16,
                  right: 16,
                  bottom: _controlsVisible ? 16 : -148,
                  child: _ReaderBottomPanel(
                    title: '$currentPage / ${images.length}',
                    currentPage: currentPage,
                    pageCount: images.length,
                    onChanged: (value) {
                      final target = value.round().clamp(1, images.length);
                      _moveToPage(target - 1);
                    },
                    onPrevChapter: _previousChapter,
                    onPrevPage: _goToPreviousPage,
                    onNextPage: _goToNextPage,
                    onNextChapter: _nextChapter,
                    showDownload: !_isPureLocalReader,
                    isFullscreen: _isFullscreen,
                    autoPageEnabled: _autoPageTimer != null,
                    onDownload: _downloadFromReader,
                    onToggleFullscreen: _toggleFullscreen,
                    onToggleAutoPage: _toggleAutoPage,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_ChapterItem> get _chapterItems {
    final localComic = widget.localComic;
    if (localComic != null) {
      return localComic.chapters
          .map((chapter) => _ChapterItem(id: chapter.id, title: chapter.title))
          .toList();
    }

    final localLibraryComic = widget.localLibraryComic;
    if (localLibraryComic != null) {
      return localLibraryComic.chapters
          .map((chapter) => _ChapterItem(id: chapter.id, title: chapter.title))
          .toList();
    }

    final chapters = currentChapters;
    if (chapters == null) {
      return const <_ChapterItem>[];
    }

    final items = <_ChapterItem>[];
    if (chapters.isGrouped) {
      for (final group in chapters.groupedChapters!.entries) {
        for (final chapter in group.value.entries) {
          items.add(
            _ChapterItem(
              id: chapter.key,
              title: chapter.value,
              groupTitle: group.key,
            ),
          );
        }
      }
    } else {
      for (final chapter in chapters.chapters!.entries) {
        items.add(_ChapterItem(id: chapter.key, title: chapter.value));
      }
    }
    return items;
  }

  Future<void> _loadChapter({
    required int initialPage,
    bool preferContextLoad = false,
  }) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      _resolveCurrentChapter();
      if (widget.localComic != null) {
        final chapter = _resolveLocalChapter();
        currentChapterId = chapter.id;
        currentChapterTitle = chapter.title;
        images = _localChapterImages(chapter);
      } else if (widget.localLibraryComic != null) {
        final chapter = _resolveLocalLibraryChapter();
        currentChapterId = chapter.id;
        currentChapterTitle = chapter.title;
        images = _localLibraryChapterImages(chapter);
      } else {
        final source = PluginRuntimeController.instance.find(widget.sourceKey);
        final comicCapability = source?.comic;
        if (comicCapability == null) {
          throw StateError('Source does not support reading.');
        }

        if (preferContextLoad) {
          await _ensureContext(comicCapability);
        }

        PluginResult<List<String>> response = await comicCapability.loadEpisode(
          widget.comicId,
          currentChapterId,
        );

        if (response.isError && !_attemptedContextLoad) {
          await _ensureContext(comicCapability);
          _resolveCurrentChapter();
          response = await comicCapability.loadEpisode(
            widget.comicId,
            currentChapterId,
          );
        }

        if (response.isError) {
          throw StateError(response.errorMessage!);
        }

        images = response.data;
      }

      if (images.isEmpty) {
        currentPage = 1;
      } else if (initialPage < 1) {
        currentPage = 1;
      } else if (initialPage > images.length) {
        currentPage = images.length;
      } else {
        currentPage = initialPage;
      }

      pageController?.dispose();
      pageController = PageController(initialPage: currentPage - 1);
      _pageControllerMode = SettingsController.instance.readerPageMode;
      _isCurrentImageZoomed = false;
      _prefetchAround(currentPage);
      await _recordHistory();
    } catch (err) {
      error = err.toString();
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _ensureContext(PluginComicCapability capability) async {
    if (_attemptedContextLoad) {
      return;
    }
    _attemptedContextLoad = true;

    final response = await capability.loadInfo(widget.comicId);
    if (response.isError) {
      throw StateError(response.errorMessage!);
    }

    final details = response.data;
    if (details.title.isNotEmpty) {
      currentComicTitle = details.title;
    }
    currentSubtitle = details.subtitle ?? currentSubtitle;
    if (details.cover.isNotEmpty) {
      currentCover = details.cover;
    }
    if (details.chapters != null) {
      currentChapters = details.chapters;
    }
  }

  void _resolveCurrentChapter() {
    final chapterItems = _chapterItems;
    if (chapterItems.isEmpty) {
      currentChapterTitle = currentChapterTitle.isEmpty
          ? 'Read'
          : currentChapterTitle;
      return;
    }

    for (final chapter in chapterItems) {
      if (chapter.id == currentChapterId) {
        currentChapterTitle = chapter.title;
        return;
      }
    }
    for (final chapter in chapterItems) {
      if (chapter.title == currentChapterTitle) {
        currentChapterId = chapter.id;
        currentChapterTitle = chapter.title;
        return;
      }
    }

    currentChapterId = chapterItems.first.id;
    currentChapterTitle = chapterItems.first.title;
  }

  DownloadedChapter _resolveLocalChapter() {
    final localComic = widget.localComic;
    if (localComic == null || localComic.chapters.isEmpty) {
      throw StateError('No downloaded chapters available.');
    }

    for (final chapter in localComic.chapters) {
      if (chapter.id == currentChapterId) {
        return chapter;
      }
    }
    for (final chapter in localComic.chapters) {
      if (chapter.title == currentChapterTitle) {
        currentChapterId = chapter.id;
        return chapter;
      }
    }

    currentChapterId = localComic.chapters.first.id;
    currentChapterTitle = localComic.chapters.first.title;
    return localComic.chapters.first;
  }

  LocalLibraryChapter _resolveLocalLibraryChapter() {
    final localLibraryComic = widget.localLibraryComic;
    if (localLibraryComic == null || localLibraryComic.chapters.isEmpty) {
      throw StateError('No local chapters available.');
    }

    for (final chapter in localLibraryComic.chapters) {
      if (chapter.id == currentChapterId) {
        return chapter;
      }
    }
    for (final chapter in localLibraryComic.chapters) {
      if (chapter.title == currentChapterTitle) {
        currentChapterId = chapter.id;
        return chapter;
      }
    }

    currentChapterId = localLibraryComic.chapters.first.id;
    currentChapterTitle = localLibraryComic.chapters.first.title;
    return localLibraryComic.chapters.first;
  }

  List<String> _localChapterImages(DownloadedChapter chapter) {
    final directory = Directory(chapter.path);
    if (!directory.existsSync()) {
      return const <String>[];
    }

    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  p.basenameWithoutExtension(file.path).toLowerCase() != 'cover',
            )
            .toList()
          ..sort((a, b) => naturalComparePaths(a.path, b.path));
    return files.map((file) => file.path).toList();
  }

  List<String> _localLibraryChapterImages(LocalLibraryChapter chapter) {
    final directory = Directory(chapter.path);
    if (!directory.existsSync()) {
      return const <String>[];
    }

    final files = directory.listSync().whereType<File>().toList()
      ..sort((a, b) => naturalComparePaths(a.path, b.path));
    return files.map((file) => file.path).toList();
  }

  Future<void> _showChapterSelector() async {
    final selected = await showModalBottomSheet<_ChapterItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _chapterItems.length,
            itemBuilder: (context, index) {
              final chapter = _chapterItems[index];
              return ListTile(
                title: Text(chapter.title),
                subtitle: chapter.groupTitle == null
                    ? null
                    : Text(chapter.groupTitle!),
                selected: chapter.id == currentChapterId,
                onTap: () => Navigator.of(context).pop(chapter),
              );
            },
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }
    currentChapterId = selected.id;
    currentChapterTitle = selected.title;
    await _loadChapter(initialPage: 1);
  }

  Future<void> _previousChapter({bool toLastPage = false}) async {
    if (_chapterItems.isEmpty) {
      return;
    }
    final currentIndex = _chapterItems.indexWhere(
      (item) => item.id == currentChapterId,
    );
    if (currentIndex <= 0) {
      return;
    }
    final chapter = _chapterItems[currentIndex - 1];
    currentChapterId = chapter.id;
    currentChapterTitle = chapter.title;
    await _loadChapter(initialPage: toLastPage ? 1 << 30 : 1);
  }

  Future<void> _nextChapter() async {
    if (_chapterItems.isEmpty) {
      return;
    }
    final currentIndex = _chapterItems.indexWhere(
      (item) => item.id == currentChapterId,
    );
    if (currentIndex < 0 || currentIndex >= _chapterItems.length - 1) {
      return;
    }
    final chapter = _chapterItems[currentIndex + 1];
    currentChapterId = chapter.id;
    currentChapterTitle = chapter.title;
    await _loadChapter(initialPage: 1);
  }

  Future<void> _goToPreviousPage() async {
    if (currentPage > 1) {
      await _moveToPage(currentPage - 2);
      return;
    }
    await _previousChapter(toLastPage: true);
  }

  Future<void> _goToNextPage() async {
    if (currentPage < images.length) {
      await _moveToPage(currentPage);
      return;
    }
    await _nextChapter();
  }

  Future<void> _goToFirstPage() {
    return _moveToPage(0);
  }

  Future<void> _goToLastPage() {
    final lastPage = images.isEmpty ? 0 : images.length - 1;
    return _moveToPage(lastPage);
  }

  Future<void> _moveToPage(int pageIndex) {
    final controller = pageController;
    if (controller == null) {
      return Future<void>.value();
    }
    if (!SettingsController.instance.readerEnablePageAnimation) {
      controller.jumpToPage(pageIndex);
      return Future<void>.value();
    }
    return controller.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  GlobalKey<_ReaderImageState> _imageKeyFor(int index) {
    return _imageKeys.putIfAbsent(
      index,
      () => GlobalKey<_ReaderImageState>(debugLabel: 'reader_image_$index'),
    );
  }

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    final previous = _pendingTapDetails;
    final previousPosition = previous?.globalPosition;
    if (previousPosition != null &&
        (details.globalPosition - previousPosition).distanceSquared <=
            _doubleTapMaxDistanceSquared) {
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      _pendingTapDetails = null;
      _handleDoubleTap(details);
      return;
    }

    if (previous != null) {
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      _handleSingleTap(previous, viewportSize);
    }

    _pendingTapDetails = details;
    _pendingTapTimer = Timer(_doubleTapMaxDelay, () {
      final pending = _pendingTapDetails;
      if (pending == details) {
        _pendingTapDetails = null;
        _pendingTapTimer = null;
        _handleSingleTap(details, viewportSize);
      }
    });
  }

  void _handleSingleTap(TapUpDetails details, Size viewportSize) {
    final width = viewportSize.width;
    final height = viewportSize.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final settings = SettingsController.instance;
    if (_isCurrentImageZoomed) {
      setState(() {
        _controlsVisible = !_controlsVisible;
      });
      return;
    }
    if (settings.readerEnableTapToTurnPages) {
      final pageMode = settings.readerPageMode;
      final isVertical =
          pageMode == ReaderPageMode.continuousTopToBottom;
      final isRtl = pageMode == ReaderPageMode.galleryRightToLeft;

      // Right-to-left mode swaps which side is "previous". The user's
      // `readerReverseTapToTurnPages` toggle still applies on top of this
      // so people can further customize their preferred mapping.
      final naturalReverse =
          isRtl ^ settings.readerReverseTapToTurnPages;
      final tapPrev = naturalReverse ? _goToNextPage : _goToPreviousPage;
      final tapNext = naturalReverse ? _goToPreviousPage : _goToNextPage;

      if (isVertical) {
        final localDy = details.localPosition.dy;
        // Vertical reader uses top/bottom tap zones; reverse here is
        // intentionally ignored because scrolling direction itself is fixed
        // top-to-bottom in webtoon layout.
        final verticalPrev = settings.readerReverseTapToTurnPages
            ? _goToNextPage
            : _goToPreviousPage;
        final verticalNext = settings.readerReverseTapToTurnPages
            ? _goToPreviousPage
            : _goToNextPage;
        if (localDy < height * _tapToTurnPagePercent) {
          verticalPrev();
          return;
        }
        if (localDy > height * (1 - _tapToTurnPagePercent)) {
          verticalNext();
          return;
        }
      } else {
        final localDx = details.localPosition.dx;
        if (localDx < width * _tapToTurnPagePercent) {
          tapPrev();
          return;
        }
        if (localDx > width * (1 - _tapToTurnPagePercent)) {
          tapNext();
          return;
        }
      }
    }
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
  }

  void _handleDoubleTap(TapUpDetails details) {
    if (!SettingsController.instance.readerEnableDoubleTapZoom) {
      return;
    }
    _imageKeyFor(
      currentPage - 1,
    ).currentState?.toggleDoubleTapZoom(details.globalPosition);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyW) {
      _goToPreviousPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.keyS) {
      _goToNextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _goToFirstPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _goToLastPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketLeft ||
        key == LogicalKeyboardKey.comma) {
      _previousChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight ||
        key == LogicalKeyboardKey.period) {
      _nextChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _loadChapter(initialPage: currentPage);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openReaderSettings() {
    scaffoldKey.currentState?.openEndDrawer();
  }

  Future<void> _toggleFullscreen() async {
    if (Platform.isWindows) {
      await windowManager.setFullScreen(!_isFullscreen);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        _isFullscreen ? SystemUiMode.edgeToEdge : SystemUiMode.immersive,
      );
    }
    if (mounted) {
      setState(() {
        _isFullscreen = !_isFullscreen;
      });
    } else {
      _isFullscreen = !_isFullscreen;
    }
  }

  void _restoreFullscreenOnDispose() {
    if (Platform.isWindows) {
      unawaited(windowManager.setFullScreen(false));
    } else {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }

  void _toggleAutoPage() {
    if (_autoPageTimer == null) {
      _startAutoPage(showMessage: true);
    } else {
      _stopAutoPage(showMessage: true);
    }
  }

  void _startAutoPage({required bool showMessage}) {
    _autoPageTimer?.cancel();
    final duration = Duration(
      milliseconds:
          (SettingsController.instance.readerAutoPageIntervalSeconds * 1000)
              .round(),
    );
    _autoPageTimer = Timer.periodic(duration, (_) {
      unawaited(_advanceAutoPage());
    });
    if (mounted) {
      setState(() {});
      if (showMessage) {
        _showSnackBar(AppLocalizations.of(context).readerAutoPageOn);
      }
    }
  }

  void _stopAutoPage({required bool showMessage}) {
    if (_autoPageTimer == null) {
      return;
    }
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (mounted) {
      setState(() {});
      if (showMessage) {
        _showSnackBar(AppLocalizations.of(context).readerAutoPageOff);
      }
    }
  }

  Future<void> _advanceAutoPage() async {
    if (!mounted) {
      return;
    }
    if (currentPage < images.length) {
      await _goToNextPage();
      return;
    }
    final chapterItems = _chapterItems;
    final currentIndex = chapterItems.indexWhere(
      (item) => item.id == currentChapterId,
    );
    if (currentIndex >= 0 && currentIndex < chapterItems.length - 1) {
      await _nextChapter();
      return;
    }
    _stopAutoPage(showMessage: false);
  }

  Future<void> _downloadFromReader() async {
    if (_isPureLocalReader) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final source = PluginRuntimeController.instance.find(widget.sourceKey);
      final comicCapability = source?.comic;
      if (source == null || comicCapability == null) {
        throw StateError('Source does not support download.');
      }

      final detailsResult = await comicCapability.loadInfo(widget.comicId);
      if (detailsResult.isError) {
        throw StateError(detailsResult.errorMessage!);
      }
      final details = detailsResult.data;

      List<ChapterDownloadRequest>? requests;
      if (details.chapters != null) {
        requests = await _showReaderDownloadOptions(details);
        if (requests == null) {
          return;
        }
      }

      final summary = PluginComic(
        id: widget.comicId,
        title: currentComicTitle,
        cover: currentCover ?? '',
        sourceKey: widget.sourceKey,
        subtitle: currentSubtitle,
      );

      await DownloadController.instance.startDownload(
        summary: summary,
        details: details,
        chapters: requests,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.readerDownloadStarted(details.title));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString());
    }
  }

  Future<List<ChapterDownloadRequest>?> _showReaderDownloadOptions(
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

    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<List<ChapterDownloadRequest>>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentChapterId != null)
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: Text(l10n.readerDownloadCurrent),
                  onTap: () =>
                      Navigator.of(context).pop(<ChapterDownloadRequest>[
                        ChapterDownloadRequest(
                          id: currentChapterId,
                          title: currentChapterTitle,
                        ),
                      ]),
                ),
              ListTile(
                leading: const Icon(Icons.download_done_outlined),
                title: Text(l10n.readerDownloadAll),
                onTap: () => Navigator.of(context).pop(chapters),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recordHistory() {
    return HistoryController.instance.record(
      ReadingHistoryEntry(
        sourceKey: widget.sourceKey,
        comicId: widget.comicId,
        title: currentComicTitle,
        subtitle: currentSubtitle,
        cover: currentCover,
        chapterId: currentChapterId,
        chapterTitle: currentChapterTitle,
        page: currentPage,
        timestamp: DateTime.now(),
        isLocal: widget.localComic != null || widget.localLibraryComic != null,
        localComicPath: widget.localLibraryComic?.path,
        localFolderId: widget.localLibraryComic?.folderId,
      ),
    );
  }

  void _prefetchAround(int page) {
    if (widget.localComic != null || widget.localLibraryComic != null) {
      return;
    }
    final source = PluginRuntimeController.instance.find(widget.sourceKey);
    if (source == null || images.isEmpty) {
      return;
    }
    final radius = SettingsController.instance.readerPrefetchCount;
    final start = (page - 1 - 1).clamp(0, images.length - 1);
    final end = (page - 1 + radius).clamp(0, images.length - 1);
    for (var index = start; index <= end; index++) {
      unawaited(_prefetchOne(source, index));
    }
  }

  Future<void> _prefetchOne(PluginSource source, int index) async {
    final bytes = await ReaderImageCache.instance.load(
      source: source,
      comicId: widget.comicId,
      episodeId: currentChapterId ?? '0',
      imageUrl: images[index],
    );
    if (!mounted) {
      return;
    }
    await precacheImage(MemoryImage(bytes), context);
  }
}

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({
    required this.isLocal,
    required this.sourceKey,
    required this.comicId,
    required this.chapterId,
    required this.imageUrl,
    required this.index,
    required this.isActive,
    this.onZoomChanged,
    super.key,
  });

  final bool isLocal;
  final String sourceKey;
  final String comicId;
  final String chapterId;
  final String imageUrl;
  final int index;
  final bool isActive;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage>
    with TickerProviderStateMixin {
  late Future<Uint8List> _future = _loadBytes();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<Offset>? _offsetAnimation;
  bool _isZoomed = false;
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartScenePoint = Offset.zero;
  Size _viewportSize = Size.zero;

  @override
  void didUpdateWidget(covariant _ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.isLocal != widget.isLocal ||
        oldWidget.chapterId != widget.chapterId ||
        oldWidget.comicId != widget.comicId ||
        oldWidget.sourceKey != widget.sourceKey) {
      _future = _loadBytes();
      _resetZoom(animated: false);
    }
    if (oldWidget.isActive && !widget.isActive) {
      _resetZoom(animated: false);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failed to load page ${widget.index}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(snapshot.error.toString()),
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

        return LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                    ..scaleByDouble(_scale, _scale, 1, 1),
                  child: SizedBox.expand(
                    child: Center(
                      child: Image(
                        image: MemoryImage(snapshot.data!),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Uint8List> _loadBytes() async {
    if (widget.isLocal) {
      return File(widget.imageUrl).readAsBytes();
    }
    final source = PluginRuntimeController.instance.find(widget.sourceKey);
    if (source == null) {
      throw StateError('Source not found.');
    }
    return ReaderImageCache.instance.load(
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

  void toggleDoubleTapZoom(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    final targetScale = _scale > 1.05 ? 1.0 : 2.2;
    final targetOffset = targetScale == 1.0
        ? Offset.zero
        : _clampOffset(
            localPosition -
                _toScene(localPosition, scale: _scale, offset: _offset) *
                    targetScale,
            targetScale,
          );
    _animateTo(targetScale, targetOffset);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _stopAnimation();
    _gestureStartScale = _scale;
    _gestureStartOffset = _offset;
    _gestureStartScenePoint = _toScene(
      details.localFocalPoint,
      scale: _gestureStartScale,
      offset: _gestureStartOffset,
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final nextScale = (_gestureStartScale * details.scale).clamp(1.0, 4.0);
    final nextOffset = _clampOffset(
      details.localFocalPoint - _gestureStartScenePoint * nextScale,
      nextScale,
    );
    if (nextScale == _scale && nextOffset == _offset) {
      return;
    }
    setState(() {
      _scale = nextScale;
      _offset = nextOffset;
    });
    _notifyZoomChanged();
  }

  void _animateTo(double targetScale, Offset targetOffset) {
    _animationController?.dispose();
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    final curve = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(
      begin: _scale,
      end: targetScale,
    ).animate(curve);
    _offsetAnimation = Tween<Offset>(
      begin: _offset,
      end: targetOffset,
    ).animate(curve);
    animationController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _scale = _scaleAnimation!.value;
        _offset = _offsetAnimation!.value;
      });
      _notifyZoomChanged();
    });
    _animationController = animationController;
    animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _notifyZoomChanged();
      }
    });
    animationController.forward();
  }

  void _resetZoom({required bool animated}) {
    if (_scale <= 1.01 && _offset == Offset.zero) {
      return;
    }
    if (animated) {
      _animateTo(1, Offset.zero);
    } else {
      _stopAnimation();
      _scale = 1;
      _offset = Offset.zero;
      _notifyZoomChanged();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _stopAnimation() {
    _animationController?.stop();
    _animationController?.dispose();
    _animationController = null;
    _scaleAnimation = null;
    _offsetAnimation = null;
  }

  Offset _toScene(
    Offset viewportPoint, {
    required double scale,
    required Offset offset,
  }) {
    return (viewportPoint - offset) / scale;
  }

  Offset _clampOffset(Offset rawOffset, double scale) {
    if (_viewportSize.isEmpty || scale <= 1) {
      return Offset.zero;
    }
    final maxDx = _viewportSize.width * (scale - 1) / 2;
    final maxDy = _viewportSize.height * (scale - 1) / 2;
    return Offset(
      rawOffset.dx.clamp(-maxDx, maxDx).toDouble(),
      rawOffset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _notifyZoomChanged() {
    final zoomed = _scale > 1.01;
    if (_isZoomed == zoomed) {
      return;
    }
    _isZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.message, required this.onRetry});

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

class _ChapterItem {
  const _ChapterItem({required this.id, required this.title, this.groupTitle});

  final String id;
  final String title;
  final String? groupTitle;
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.chapterTitle,
    required this.showChapters,
    required this.onBack,
    required this.onOpenChapters,
    required this.onOpenSettings,
  });

  final String title;
  final String chapterTitle;
  final bool showChapters;
  final VoidCallback onBack;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChapters)
                IconButton(
                  onPressed: onOpenChapters,
                  icon: const Icon(Icons.menu_book_outlined),
                ),
              IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomPanel extends StatelessWidget {
  const _ReaderBottomPanel({
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.onChanged,
    required this.onPrevChapter,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onNextChapter,
    required this.showDownload,
    required this.isFullscreen,
    required this.autoPageEnabled,
    required this.onDownload,
    required this.onToggleFullscreen,
    required this.onToggleAutoPage,
  });

  final String title;
  final int currentPage;
  final int pageCount;
  final ValueChanged<double> onChanged;
  final VoidCallback onPrevChapter;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final VoidCallback onNextChapter;
  final bool showDownload;
  final bool isFullscreen;
  final bool autoPageEnabled;
  final VoidCallback onDownload;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleAutoPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Slider(
              value: currentPage.toDouble().clamp(
                1,
                pageCount == 0 ? 1 : pageCount.toDouble(),
              ),
              min: 1,
              max: pageCount <= 1 ? 1 : pageCount.toDouble(),
              divisions: pageCount <= 1 ? 1 : pageCount - 1,
              onChanged: pageCount <= 1 ? null : onChanged,
            ),
            Row(
              children: [
                IconButton(
                  onPressed: onPrevChapter,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  onPressed: onPrevPage,
                  icon: const Icon(Icons.chevron_left),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onNextPage,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  onPressed: onNextChapter,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  if (showDownload)
                    _ReaderUtilityButton(
                      icon: Icons.download_outlined,
                      label: AppLocalizations.of(context).readerDownload,
                      onPressed: onDownload,
                    ),
                  _ReaderUtilityButton(
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    label: isFullscreen
                        ? AppLocalizations.of(context).readerExitFullscreen
                        : AppLocalizations.of(context).readerFullscreen,
                    onPressed: onToggleFullscreen,
                  ),
                  _ReaderUtilityButton(
                    icon: autoPageEnabled
                        ? Icons.pause_circle_outline
                        : Icons.timer_outlined,
                    label: AppLocalizations.of(context).readerAutoPageInterval,
                    selected: autoPageEnabled,
                    onPressed: onToggleAutoPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderUtilityButton extends StatelessWidget {
  const _ReaderUtilityButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ReaderTapGuide extends StatelessWidget {
  const _ReaderTapGuide({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Center: menu  Double tap: zoom',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsDrawer extends StatelessWidget {
  const _ReaderSettingsDrawer({
    required this.onClose,
    required this.tapToTurn,
    required this.reverseTapToTurn,
    required this.doubleTapZoom,
    required this.pageAnimation,
    required this.autoPageIntervalSeconds,
    required this.pageMode,
    required this.onTapToTurnChanged,
    required this.onReverseTapToTurnChanged,
    required this.onDoubleTapZoomChanged,
    required this.onPageAnimationChanged,
    required this.onAutoPageIntervalChanged,
    required this.onPageModeChanged,
  });

  final VoidCallback onClose;
  final bool tapToTurn;
  final bool reverseTapToTurn;
  final bool doubleTapZoom;
  final bool pageAnimation;
  final double autoPageIntervalSeconds;
  final ReaderPageMode pageMode;
  final ValueChanged<bool> onTapToTurnChanged;
  final ValueChanged<bool> onReverseTapToTurnChanged;
  final ValueChanged<bool> onDoubleTapZoomChanged;
  final ValueChanged<bool> onPageAnimationChanged;
  final ValueChanged<double> onAutoPageIntervalChanged;
  final ValueChanged<ReaderPageMode> onPageModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Drawer(
      width: 360,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: Text(
                l10n.readerSettings,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: onClose,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  ListTile(
                    title: Text(l10n.readerDirection),
                    subtitle: Text(_pageModeLabel(l10n, pageMode)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: SegmentedButton<ReaderPageMode>(
                      segments: [
                        ButtonSegment(
                          value: ReaderPageMode.galleryLeftToRight,
                          icon: const Icon(Icons.east),
                          tooltip: l10n.readerDirectionLeftToRight,
                        ),
                        ButtonSegment(
                          value: ReaderPageMode.galleryRightToLeft,
                          icon: const Icon(Icons.west),
                          tooltip: l10n.readerDirectionRightToLeft,
                        ),
                        ButtonSegment(
                          value: ReaderPageMode.continuousTopToBottom,
                          icon: const Icon(Icons.south),
                          tooltip: l10n.readerDirectionTopToBottom,
                        ),
                      ],
                      selected: <ReaderPageMode>{pageMode},
                      onSelectionChanged: (set) => onPageModeChanged(set.first),
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: Text(l10n.readerTapToTurn),
                    value: tapToTurn,
                    onChanged: onTapToTurnChanged,
                  ),
                  SwitchListTile(
                    title: Text(l10n.readerReverseTapToTurn),
                    value: reverseTapToTurn,
                    onChanged: tapToTurn ? onReverseTapToTurnChanged : null,
                  ),
                  SwitchListTile(
                    title: Text(l10n.readerPageAnimation),
                    value: pageAnimation,
                    onChanged: onPageAnimationChanged,
                  ),
                  SwitchListTile(
                    title: Text(l10n.readerDoubleTapZoom),
                    value: doubleTapZoom,
                    onChanged: onDoubleTapZoomChanged,
                  ),
                  ListTile(
                    title: Text(l10n.readerAutoPageInterval),
                    subtitle: Text(l10n.readerSeconds(autoPageIntervalSeconds)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Slider(
                      value: autoPageIntervalSeconds,
                      min: 1,
                      max: 15,
                      divisions: 28,
                      label: autoPageIntervalSeconds.toStringAsFixed(1),
                      onChanged: onAutoPageIntervalChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _pageModeLabel(AppLocalizations l10n, ReaderPageMode mode) {
  return switch (mode) {
    ReaderPageMode.galleryLeftToRight => l10n.readerDirectionLeftToRight,
    ReaderPageMode.galleryRightToLeft => l10n.readerDirectionRightToLeft,
    ReaderPageMode.continuousTopToBottom => l10n.readerDirectionTopToBottom,
  };
}
