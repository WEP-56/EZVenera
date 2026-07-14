import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../reader/chapter_order.dart';
import '../reader/reader_image_cache.dart';
import '../settings/settings_controller.dart';
import '../utils/natural_sort.dart';
import '../utils/volume_listener.dart';

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
  ScrollController? _scrollController;
  bool _scrollControllerIsContinuous = false;
  double _continuousItemExtent = 0;
  bool _suppressScrollListener = false;
  final FocusNode focusNode = FocusNode();
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  bool _attemptedContextLoad = false;
  bool _controlsVisible = false;
  bool _isCurrentImageZoomed = false;
  TapUpDetails? _pendingTapDetails;
  Timer? _pendingTapTimer;
  final Map<int, GlobalKey<_ReaderImageState>> _imageKeys =
      <int, GlobalKey<_ReaderImageState>>{};
  final Map<int, double> _verticalPageHeights = <int, double>{};
  /// While non-null, vertical continuous mode is restoring a saved page.
  /// Height changes re-anchor to this index (0-based). No hard scroll lock —
  /// upstream uses index-based ScrollablePositionedList; we approximate that
  /// with jump + re-anchor, and cancel as soon as the user takes over.
  int? _verticalResumeTargetIndex;
  int _verticalResumeCorrections = 0;
  Timer? _verticalResumeWatchdog;

  static const _doubleTapMaxDelay = Duration(milliseconds: 150);
  // Keep correcting until the target page is measured; short safety cap only.
  static const _maxVerticalResumeCorrections = 40;
  static const _verticalResumeWatchdogInterval = Duration(milliseconds: 80);
  // ~1.2s worst-case background re-anchor; normal path ends when target is built.
  static const _verticalResumeWatchdogMaxTicks = 15;
  static const _doubleTapMaxDistanceSquared = 24.0 * 24.0;
  static const _tapToTurnPagePercent = 0.33;
  static const _longPressZoomScale = 2.5;

  bool _isFullscreen = false;
  Timer? _autoPageTimer;
  VolumeListener? _volumeListener;
  bool _isLongPressZooming = false;
  bool _longPressDragging = false;
  Offset _longPressZoomOffset = Offset.zero;
  Offset _longPressStartLocal = Offset.zero;
  bool _isProgressDragging = false;
  double? _progressDragPage;
  double _bottomPanelHeight = 0;

  bool get _isPureLocalReader =>
      widget.localComic != null || widget.localLibraryComic != null;

  @override
  void initState() {
    super.initState();
    SettingsController.instance.addListener(_onSettingsChanged);
    _updateVolumeListener();
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
    _volumeListener?.cancel();
    _volumeListener = null;
    _pendingTapTimer?.cancel();
    _verticalResumeWatchdog?.cancel();
    _verticalResumeWatchdog = null;
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (_isFullscreen) {
      _restoreFullscreenOnDispose();
    }
    // Persist the latest progress even if the user leaves without flipping
    // pages (common in vertical continuous mode after only loading a chapter).
    if (!isLoading && error == null && images.isNotEmpty) {
      // Fire-and-forget: dispose cannot await, but HistoryController.record
      // is safe to call after the widget is gone.
      _recordHistory();
    }
    focusNode.dispose();
    pageController?.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    final newMode = SettingsController.instance.readerPageMode;
    final newHorizContinuous =
        SettingsController.instance.readerHorizontalContinuous;
    final needsContinuous = _isContinuousMode(newMode, newHorizContinuous);

    if (_pageControllerMode != newMode ||
        _scrollControllerIsContinuous != needsContinuous) {
      final previousPage = currentPage;
      if (needsContinuous) {
        pageController?.dispose();
        pageController = null;
        _scrollController?.dispose();
        _scrollController = _buildScrollController();
        _scrollControllerIsContinuous = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_isVerticalContinuousMode) {
            _moveToPage(previousPage - 1);
            return;
          }
          if (_continuousItemExtent > 0) {
            _suppressScrollListener = true;
            _scrollController?.jumpTo(
              (previousPage - 1) * _continuousItemExtent,
            );
            _suppressScrollListener = false;
          }
        });
      } else {
        _scrollController?.dispose();
        _scrollController = null;
        _scrollControllerIsContinuous = false;
        pageController?.dispose();
        pageController = PageController(initialPage: previousPage - 1);
      }
      _pageControllerMode = newMode;
    }
    _updateVolumeListener();
    // Defer rebuild so this never fires inside a mouse-tracker or
    // gesture-recognizer callback (avoids _debugDuringDeviceUpdate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  bool _isContinuousMode(ReaderPageMode mode, bool horizContinuous) {
    if (mode == ReaderPageMode.continuousTopToBottom) {
      return true;
    }
    return horizContinuous;
  }

  bool get _isVerticalContinuousMode =>
      _scrollControllerIsContinuous &&
      SettingsController.instance.readerPageMode ==
          ReaderPageMode.continuousTopToBottom;

  ScrollController _buildScrollController() {
    final sc = ScrollController();
    sc.addListener(_onScrollChanged);
    return sc;
  }

  void _onScrollChanged() {
    if (_suppressScrollListener || _verticalResumeTargetIndex != null) {
      // Ignore scroll-driven page updates while restoring a saved position.
      return;
    }
    if (_isVerticalContinuousMode) {
      _updateCurrentPageFromVisibleItems();
      return;
    }
    if (_continuousItemExtent <= 0) return;

    final offset = _scrollController?.offset ?? 0;
    final estimated = (offset / _continuousItemExtent).floor() + 1;
    final clamped = estimated.clamp(1, images.isEmpty ? 1 : images.length);
    _setCurrentPageFromScroll(clamped);
  }

  void _updateCurrentPageFromVisibleItems() {
    if (images.isEmpty) {
      return;
    }

    final viewportCenter = MediaQuery.sizeOf(context).height / 2;
    var bestPage = currentPage;
    var bestDistance = double.infinity;

    for (var index = 0; index < images.length; index++) {
      final itemContext = _imageKeyFor(index).currentContext;
      final renderObject = itemContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      if (top <= viewportCenter && bottom >= viewportCenter) {
        bestPage = index + 1;
        bestDistance = 0;
        break;
      }
      final distance = top > viewportCenter
          ? top - viewportCenter
          : viewportCenter - bottom;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPage = index + 1;
      }
    }

    _setCurrentPageFromScroll(bestPage);
  }

  void _setCurrentPageFromScroll(int page) {
    if (_verticalResumeTargetIndex != null) {
      return;
    }
    final clamped = page.clamp(1, images.isEmpty ? 1 : images.length);
    if (clamped != currentPage) {
      if (_isProgressDragging) {
        return;
      }
      currentPage = clamped;
      _recordHistory();
      _prefetchAround(currentPage);
      // Defer setState so it never fires inside a mouse-tracker or
      // scroll-notification callback (avoids _debugDuringDeviceUpdate).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Attaches or detaches the Android volume-key listener to match the
  /// current user preference. The reader is the only place volume-key
  /// paging is active, so ownership of the subscription lives here.
  void _updateVolumeListener() {
    final wantsVolumeKeys =
        VolumeListener.isSupported &&
        SettingsController.instance.readerEnableVolumeKeys;
    if (wantsVolumeKeys) {
      if (_volumeListener != null) {
        return;
      }
      _volumeListener = VolumeListener(
        onUp: _handleVolumeKeyUp,
        onDown: _handleVolumeKeyDown,
      )..listen();
    } else {
      _volumeListener?.cancel();
      _volumeListener = null;
    }
  }

  void _handleVolumeKeyUp() {
    // Volume up = previous page by default; the "reverse" user preference
    // swaps it, so users who read right-to-left manga can keep the physical
    // "down is forward" mapping if they prefer.
    if (SettingsController.instance.readerReverseTapToTurnPages) {
      _goToNextPage();
    } else {
      _goToPreviousPage();
    }
  }

  void _handleVolumeKeyDown() {
    if (SettingsController.instance.readerReverseTapToTurnPages) {
      _goToPreviousPage();
    } else {
      _goToNextPage();
    }
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
        volumeKeys: SettingsController.instance.readerEnableVolumeKeys,
        horizontalContinuous:
            SettingsController.instance.readerHorizontalContinuous,
        chapterEdgeButtons:
            SettingsController.instance.readerShowChapterEdgeButtons,
        onPageModeChanged: (value) async {
          await SettingsController.instance.setReaderPageMode(value);
          if (mounted) setState(() {});
        },
        onVolumeKeysChanged: (value) async {
          await SettingsController.instance.setReaderEnableVolumeKeys(value);
          if (mounted) setState(() {});
        },
        onHorizontalContinuousChanged: (value) async {
          await SettingsController.instance.setReaderHorizontalContinuous(
            value,
          );
          if (mounted) setState(() {});
        },
        onChapterEdgeButtonsChanged: (value) async {
          await SettingsController.instance.setReaderShowChapterEdgeButtons(
            value,
          );
          if (mounted) setState(() {});
        },
        onTapToTurnChanged: (value) async {
          await SettingsController.instance.setReaderEnableTapToTurnPages(
            value,
          );
          if (mounted) setState(() {});
        },
        onReverseTapToTurnChanged: (value) async {
          await SettingsController.instance.setReaderReverseTapToTurnPages(
            value,
          );
          if (mounted) setState(() {});
        },
        onDoubleTapZoomChanged: (value) async {
          await SettingsController.instance.setReaderEnableDoubleTapZoom(value);
          if (mounted) setState(() {});
        },
        onPageAnimationChanged: (value) async {
          await SettingsController.instance.setReaderEnablePageAnimation(value);
          if (mounted) setState(() {});
        },
        onAutoPageIntervalChanged: (value) async {
          await SettingsController.instance.setReaderAutoPageIntervalSeconds(
            value,
          );
          if (_autoPageTimer != null) _startAutoPage(showMessage: false);
          if (mounted) setState(() {});
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

    if (images.isEmpty ||
        (pageController == null && _scrollController == null)) {
      return _ReaderError(
        message: 'No images returned for this chapter.',
        onRetry: () => _loadChapter(initialPage: currentPage),
      );
    }

    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent || _isCurrentImageZoomed) {
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
          final isContinuous = _scrollControllerIsContinuous;
          final isRtl = pageMode == ReaderPageMode.galleryRightToLeft;
          final isVertical = pageMode == ReaderPageMode.continuousTopToBottom;

          // Horizontal continuous still pages by viewport width. Vertical
          // continuous stitches images at their natural scaled height.
          final itemExtent = isVertical ? 0.0 : constraints.maxWidth + 2;

          final scrollContent = isContinuous
              ? _buildContinuousView(
                  constraints: constraints,
                  isVertical: isVertical,
                  isRtl: isRtl,
                  itemExtent: itemExtent,
                )
              : _buildPagedView(pageMode: pageMode, isRtl: isRtl);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, constraints.biggest),
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: _longPressDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  transform: _isLongPressZooming
                      ? (Matrix4.identity()
                          ..translateByDouble(
                            _longPressZoomOffset.dx,
                            _longPressZoomOffset.dy,
                            0,
                            1,
                          )
                          ..scaleByDouble(
                            _longPressZoomScale,
                            _longPressZoomScale,
                            1,
                            1,
                          ))
                      : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  child: scrollContent,
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
                if (_showChapterEndActions)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 16,
                    right: 16,
                    bottom: _chapterEndActionsBottom(context),
                    child: _ReaderChapterEndActions(
                      showPrevious: _showPreviousChapterAction,
                      showNext: _showNextChapterAction,
                      onPrevious: _previousChapter,
                      onNext: _nextChapter,
                    ),
                  ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  bottom: _controlsVisible
                      ? -(36 + MediaQuery.paddingOf(context).bottom)
                      : 10 + MediaQuery.paddingOf(context).bottom,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _controlsVisible ? 0 : 1,
                    child: Center(
                      child: _ReaderCollapsedProgressPill(
                        title:
                            '${_displayedProgressPage.clamp(1, images.length)} / ${images.length}',
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  left: 16,
                  right: 16,
                  bottom: _controlsVisible
                      ? 16.0
                      : -((_bottomPanelHeight > 0
                                ? _bottomPanelHeight
                                : 180.0) +
                            24.0),
                  child: _MeasuredSize(
                    onSizeChanged: _handleBottomPanelSizeChanged,
                    child: _ReaderBottomPanel(
                      title:
                          '${_displayedProgressPage.clamp(1, images.length)} / ${images.length}',
                      currentPage: _displayedProgressPage,
                      pageCount: images.length,
                      onChangeStart: _handleProgressChangeStart,
                      onChanged: _handleProgressChanged,
                      onChangeEnd: _handleProgressChangeEnd,
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int get _displayedProgressPage {
    final dragged = _progressDragPage;
    if (dragged == null || images.isEmpty) {
      return currentPage;
    }
    return dragged.round().clamp(1, images.length);
  }

  int get _currentChapterIndex {
    return _chapterItems.indexWhere((item) => item.id == currentChapterId);
  }

  bool get _hasPreviousChapter {
    final index = _currentChapterIndex;
    return _chapterItems.length > 1 && index > 0;
  }

  bool get _hasNextChapter {
    final index = _currentChapterIndex;
    return _chapterItems.length > 1 &&
        index >= 0 &&
        index < _chapterItems.length - 1;
  }

  bool get _showPreviousChapterAction {
    return images.isNotEmpty && currentPage <= 1 && _hasPreviousChapter;
  }

  bool get _showNextChapterAction {
    return images.isNotEmpty && currentPage >= images.length && _hasNextChapter;
  }

  bool get _showChapterEndActions {
    return SettingsController.instance.readerShowChapterEdgeButtons &&
        (_showPreviousChapterAction || _showNextChapterAction);
  }

  double _chapterEndActionsBottom(BuildContext context) {
    if (_controlsVisible) {
      final panelHeight = _bottomPanelHeight > 0 ? _bottomPanelHeight : 180.0;
      return 16 + panelHeight + 10;
    }

    return MediaQuery.paddingOf(context).bottom + 44;
  }

  void _handleBottomPanelSizeChanged(Size size) {
    final height = size.height;
    if (height <= 0 || (_bottomPanelHeight - height).abs() < 1) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _bottomPanelHeight = height;
        });
      }
    });
  }

  void _handleProgressChangeStart(double value) {
    _pendingTapTimer?.cancel();
    _pendingTapTimer = null;
    _pendingTapDetails = null;
    _stopLongPressZoom();
    setState(() {
      _isProgressDragging = true;
      _progressDragPage = value;
    });
  }

  void _handleProgressChanged(double value) {
    if (!_isProgressDragging) {
      _isProgressDragging = true;
    }
    setState(() {
      _progressDragPage = value;
    });
  }

  Future<void> _handleProgressChangeEnd(double value) async {
    final target = value.round().clamp(1, images.length);
    setState(() {
      _isProgressDragging = false;
      _progressDragPage = target.toDouble();
      currentPage = target;
      _isCurrentImageZoomed = false;
    });
    await _moveToPage(target - 1);
    if (!mounted) {
      return;
    }
    setState(() {
      _progressDragPage = null;
    });
    _recordHistory();
    _prefetchAround(currentPage);
  }

  void _stopLongPressZoom() {
    if (!_isLongPressZooming && !_longPressDragging) {
      return;
    }
    _isLongPressZooming = false;
    _longPressDragging = false;
    _longPressZoomOffset = Offset.zero;
  }

  Widget _buildContinuousView({
    required BoxConstraints constraints,
    required bool isVertical,
    required bool isRtl,
    required double itemExtent,
  }) {
    _continuousItemExtent = itemExtent;

    final list = ListView.builder(
      key: ValueKey<String>(
        'continuous_${isVertical
            ? 'v'
            : isRtl
            ? 'rtl'
            : 'ltr'}',
      ),
      controller: _scrollController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      reverse: isRtl,
      physics: _isCurrentImageZoomed
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final reservedHeight = isVertical
            ? (_verticalPageHeights[index] ?? _averageVerticalPageHeight())
            : null;
        final image = _ReaderImage(
          key: _imageKeyFor(index),
          isLocal:
              widget.localComic != null || widget.localLibraryComic != null,
          sourceKey: widget.sourceKey,
          comicId: widget.comicId,
          chapterId: currentChapterId ?? '0',
          imageUrl: images[index],
          index: index + 1,
          isActive: index + 1 == currentPage,
          fitWidth: isVertical,
          reservedHeight: reservedHeight,
          onSizeChanged: isVertical
              ? (height) => _rememberVerticalPageHeight(index, height)
              : null,
          onZoomChanged: (zoomed) {
            if (!mounted) return;
            if (_isCurrentImageZoomed != zoomed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _isCurrentImageZoomed = zoomed);
              });
            }
          },
        );

        if (isVertical) {
          return image;
        }

        final hasSeparator = index < images.length - 1;
        return SizedBox(
          width: constraints.maxWidth + (hasSeparator ? 2 : 0),
          height: constraints.maxHeight,
          child: Row(
            children: [
              SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: image,
              ),
              if (hasSeparator)
                const SizedBox(
                  width: 2,
                  child: ColoredBox(color: Colors.black),
                ),
            ],
          ),
        );
      },
    );

    // Like upstream: no hard lock. If the user starts scrolling during restore,
    // stop re-anchoring immediately so we don't fight their gesture.
    if (!isVertical) {
      return list;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_verticalResumeTargetIndex == null) {
          return false;
        }
        final isUserDrag = notification is ScrollStartNotification &&
            notification.dragDetails != null;
        final isUserScroll = notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle;
        if (isUserDrag || isUserScroll) {
          _finishVerticalResume();
        }
        return false;
      },
      child: list,
    );
  }

  Widget _buildPagedView({
    required ReaderPageMode pageMode,
    required bool isRtl,
  }) {
    return PageView.builder(
      key: ValueKey<ReaderPageMode>(pageMode),
      controller: pageController,
      itemCount: images.length,
      scrollDirection: Axis.horizontal,
      reverse: isRtl,
      physics: _isCurrentImageZoomed
          ? const NeverScrollableScrollPhysics()
          : null,
      onPageChanged: (index) {
        currentPage = index + 1;
        _isCurrentImageZoomed = false;
        _recordHistory();
        _prefetchAround(currentPage);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      itemBuilder: (context, index) {
        return _ReaderImage(
          key: _imageKeyFor(index),
          isLocal:
              widget.localComic != null || widget.localLibraryComic != null,
          sourceKey: widget.sourceKey,
          comicId: widget.comicId,
          chapterId: currentChapterId ?? '0',
          imageUrl: images[index],
          index: index + 1,
          isActive: index + 1 == currentPage,
          onZoomChanged: (zoomed) {
            if (!mounted || currentPage != index + 1) return;
            if (_isCurrentImageZoomed != zoomed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _isCurrentImageZoomed = zoomed);
              });
            }
          },
        );
      },
    );
  }

  List<_ChapterItem> get _chapterItems {
    final reversed = _chaptersReversed;
    final localComic = widget.localComic;
    if (localComic != null) {
      final chapters = reversed
          ? localComic.chapters.reversed
          : localComic.chapters;
      return chapters
          .map((chapter) => _ChapterItem(id: chapter.id, title: chapter.title))
          .toList();
    }

    final localLibraryComic = widget.localLibraryComic;
    if (localLibraryComic != null) {
      final chapters = reversed
          ? localLibraryComic.chapters.reversed
          : localLibraryComic.chapters;
      return chapters
          .map((chapter) => _ChapterItem(id: chapter.id, title: chapter.title))
          .toList();
    }

    final chapters = currentChapters;
    if (chapters == null) {
      return const <_ChapterItem>[];
    }

    final items = <_ChapterItem>[];
    if (chapters.isGrouped) {
      for (final group in orderedChapterGroups(
        chapters.groupedChapters!,
        reversed,
      )) {
        for (final chapter in orderedChapterEntries(group.value, reversed)) {
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
      for (final chapter in orderedChapterEntries(
        chapters.chapters!,
        reversed,
      )) {
        items.add(_ChapterItem(id: chapter.key, title: chapter.value));
      }
    }
    return items;
  }

  bool get _chaptersReversed =>
      isChapterOrderReversedFor(widget.sourceKey, widget.comicId);

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
      _scrollController?.dispose();
      _scrollController = null;
      _scrollControllerIsContinuous = false;
      _verticalPageHeights.clear();

      final mode = SettingsController.instance.readerPageMode;
      final horizContinuous =
          SettingsController.instance.readerHorizontalContinuous;
      if (_isContinuousMode(mode, horizContinuous)) {
        _scrollController = _buildScrollController();
        _scrollControllerIsContinuous = true;
        pageController = null;
        if (mode == ReaderPageMode.continuousTopToBottom && currentPage > 1) {
          // Restore by jump + re-anchor as real image heights arrive.
          // Animated resume stacks with early user flings and overshoots.
          _beginVerticalResume(currentPage - 1);
        } else {
          _clearVerticalResume();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_isVerticalContinuousMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final target = _verticalResumeTargetIndex;
              if (target != null) {
                _jumpToVerticalPage(target);
              } else {
                _moveToPage(currentPage - 1);
              }
            });
            return;
          }
          if (_continuousItemExtent > 0) {
            _suppressScrollListener = true;
            _scrollController?.jumpTo(
              (currentPage - 1) * _continuousItemExtent,
            );
            _suppressScrollListener = false;
          }
        });
      } else {
        _clearVerticalResume();
        pageController = PageController(initialPage: currentPage - 1);
      }
      _pageControllerMode = mode;
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
                  p.basenameWithoutExtension(file.path).toLowerCase() !=
                  'cover',
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
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final reversed = _chaptersReversed;
            final chapterItems = _chapterItems;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Chapters',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await _setChapterOrderReversed(!reversed);
                              if (!context.mounted) {
                                return;
                              }
                              if (mounted) {
                                setState(() {});
                              }
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.swap_vert, size: 18),
                            label: Text(reversed ? 'Original' : 'Reverse'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: chapterItems.length,
                        itemBuilder: (context, index) {
                          final chapter = chapterItems[index];
                          return ListTile(
                            title: Text(chapter.title),
                            subtitle: chapter.groupTitle == null
                                ? null
                                : Text(chapter.groupTitle!),
                            trailing: chapter.id == currentChapterId
                                ? const Icon(Icons.check)
                                : const Icon(Icons.chevron_right),
                            selected: chapter.id == currentChapterId,
                            onTap: () => Navigator.of(context).pop(chapter),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

  Future<void> _setChapterOrderReversed(bool reversed) async {
    await setChapterOrderReversedFor(
      widget.sourceKey,
      widget.comicId,
      reversed,
    );
    _resolveCurrentChapter();
    await _recordHistory();
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
    if (_scrollControllerIsContinuous) {
      if (currentPage > 1) {
        await _moveToPage(currentPage - 2);
      }
      return;
    }
    if (currentPage > 1) {
      await _moveToPage(currentPage - 2);
      return;
    }
    await _previousChapter(toLastPage: true);
  }

  Future<void> _goToNextPage() async {
    if (_scrollControllerIsContinuous) {
      if (currentPage < images.length) {
        await _moveToPage(currentPage);
      }
      return;
    }
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
    if (_scrollControllerIsContinuous) {
      final targetIndex = pageIndex.clamp(
        0,
        images.isEmpty ? 0 : images.length - 1,
      );
      if (_isVerticalContinuousMode) {
        return _moveToVerticalPage(targetIndex);
      }
      final sc = _scrollController;
      if (sc == null || !sc.hasClients || _continuousItemExtent <= 0) {
        return Future<void>.value();
      }
      final target = targetIndex * _continuousItemExtent;
      if (SettingsController.instance.readerEnablePageAnimation) {
        return sc.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        sc.jumpTo(target);
        return Future<void>.value();
      }
    }
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

  Future<void> _moveToVerticalPage(int targetIndex) async {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) {
      return;
    }

    // Explicit user jumps (chapter chrome / progress bar) cancel an in-flight
    // resume so we don't fight the user after they pick a new page.
    if (_verticalResumeTargetIndex != null &&
        _verticalResumeTargetIndex != targetIndex) {
      _finishVerticalResume();
    }

    final itemContext = _imageKeyFor(targetIndex).currentContext;
    if (itemContext != null) {
      final animate = SettingsController.instance.readerEnablePageAnimation &&
          _verticalResumeTargetIndex == null;
      await Scrollable.ensureVisible(
        itemContext,
        alignment: 0,
        duration: animate
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        curve: Curves.easeOut,
      );
      return;
    }

    _jumpToVerticalPage(targetIndex);

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _verticalResumeTargetIndex != null) {
      // Resume path keeps re-anchoring from height callbacks; don't animate.
      return;
    }
    final nextContext = _imageKeyFor(targetIndex).currentContext;
    if (nextContext != null && nextContext.mounted) {
      final animate = SettingsController.instance.readerEnablePageAnimation;
      await Scrollable.ensureVisible(
        nextContext,
        alignment: 0,
        duration: animate
            ? const Duration(milliseconds: 120)
            : Duration.zero,
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToVerticalPage(int targetIndex) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) {
      return;
    }

    final itemContext = _imageKeyFor(targetIndex).currentContext;
    if (itemContext != null) {
      _suppressScrollListener = true;
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0,
        duration: Duration.zero,
      );
      _suppressScrollListener = false;
      currentPage = targetIndex + 1;
      return;
    }

    final target = _estimatedVerticalOffsetFor(
      targetIndex,
    ).clamp(sc.position.minScrollExtent, sc.position.maxScrollExtent);
    _suppressScrollListener = true;
    sc.jumpTo(target);
    _suppressScrollListener = false;
    currentPage = targetIndex + 1;
  }

  double _estimatedVerticalOffsetFor(int targetIndex) {
    var offset = 0.0;
    final fallbackHeight = _averageVerticalPageHeight();
    for (var index = 0; index < targetIndex; index++) {
      offset += _verticalPageHeights[index] ?? fallbackHeight;
    }
    return offset;
  }

  double _averageVerticalPageHeight() {
    if (_verticalPageHeights.isEmpty) {
      // Webtoon pages are typically taller than one viewport. Using viewport
      // height alone underestimates total length and makes mid-chapter resume
      // land too early, then "catch up" as real heights expand.
      final height = MediaQuery.sizeOf(context).height;
      final base = height <= 0 ? 720.0 : height;
      return base * 2.2;
    }
    final total = _verticalPageHeights.values.fold<double>(
      0,
      (sum, height) => sum + height,
    );
    return total / _verticalPageHeights.length;
  }

  void _rememberVerticalPageHeight(int index, double height) {
    if (height <= 0) {
      return;
    }
    final previous = _verticalPageHeights[index];
    if (previous != null && (previous - height).abs() < 1) {
      return;
    }
    final usedEstimate = previous == null;
    final estimateBefore = usedEstimate ? _averageVerticalPageHeight() : null;
    _verticalPageHeights[index] = height;

    if (!_isVerticalContinuousMode) {
      return;
    }

    final resumeTarget = _verticalResumeTargetIndex;
    if (resumeTarget != null) {
      // Only heights at/above the resume target affect its anchor.
      if (index > resumeTarget) {
        return;
      }
      // Keep re-anchoring until the restored page is laid out with a real size
      // (or we hit the correction cap). Jump only — never animate.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _verticalResumeTargetIndex != resumeTarget) {
          return;
        }
        _jumpToVerticalPage(resumeTarget);
        _verticalResumeCorrections++;
        final targetMeasured = _verticalPageHeights.containsKey(resumeTarget);
        final targetBuilt =
            _imageKeyFor(resumeTarget).currentContext != null;
        if ((targetMeasured && targetBuilt) ||
            _verticalResumeCorrections >= _maxVerticalResumeCorrections) {
          _finishVerticalResume();
        }
      });
      return;
    }

    // Outside resume: if a page above the viewport grows/shrinks, shift the
    // scroll offset by the delta so the visible content does not jump.
    final delta = height - (previous ?? estimateBefore ?? height);
    if (delta.abs() < 1) {
      return;
    }
    _compensateVerticalScrollForHeightChange(index, delta);
  }

  void _compensateVerticalScrollForHeightChange(int index, double delta) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) {
      return;
    }
    final offset = sc.offset;
    // If the changed page starts at or below the current scroll position, the
    // content under the viewport is unaffected.
    final pageStart = _estimatedVerticalOffsetFor(index);
    if (offset <= pageStart + 0.5) {
      return;
    }
    final next = (offset + delta).clamp(
      sc.position.minScrollExtent,
      sc.position.maxScrollExtent,
    );
    if ((next - offset).abs() < 1) {
      return;
    }
    _suppressScrollListener = true;
    sc.jumpTo(next);
    _suppressScrollListener = false;
  }

  void _beginVerticalResume(int targetIndex) {
    _verticalResumeWatchdog?.cancel();
    _verticalResumeTargetIndex = targetIndex;
    _verticalResumeCorrections = 0;
    var ticks = 0;
    // Re-jump on a timer too: if the estimate overshoots, only pages past the
    // target may load, and height callbacks for index > target are ignored.
    // Periodic jumps re-sample the growing average until the target is built.
    _verticalResumeWatchdog = Timer.periodic(
      _verticalResumeWatchdogInterval,
      (timer) {
        if (!mounted || _verticalResumeTargetIndex == null) {
          timer.cancel();
          return;
        }
        final target = _verticalResumeTargetIndex!;
        _jumpToVerticalPage(target);
        ticks++;
        final targetMeasured = _verticalPageHeights.containsKey(target);
        final targetBuilt = _imageKeyFor(target).currentContext != null;
        if ((targetMeasured && targetBuilt) ||
            ticks >= _verticalResumeWatchdogMaxTicks ||
            _verticalResumeCorrections >= _maxVerticalResumeCorrections) {
          _finishVerticalResume();
        }
      },
    );
  }

  void _clearVerticalResume() {
    _verticalResumeWatchdog?.cancel();
    _verticalResumeWatchdog = null;
    _verticalResumeTargetIndex = null;
    _verticalResumeCorrections = 0;
  }

  void _finishVerticalResume() {
    if (_verticalResumeTargetIndex == null &&
        _verticalResumeWatchdog == null) {
      return;
    }
    _clearVerticalResume();
  }

  GlobalKey<_ReaderImageState> _imageKeyFor(int index) {
    return _imageKeys.putIfAbsent(
      index,
      () => GlobalKey<_ReaderImageState>(debugLabel: 'reader_image_$index'),
    );
  }

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    final doubleTapEnabled =
        SettingsController.instance.readerEnableDoubleTapZoom;

    if (!doubleTapEnabled) {
      // No double-tap detection needed — respond to every tap immediately.
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      _pendingTapDetails = null;
      _handleSingleTap(details, viewportSize);
      return;
    }

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
      setState(() => _controlsVisible = !_controlsVisible);
      return;
    }
    if (settings.readerEnableTapToTurnPages) {
      final pageMode = settings.readerPageMode;
      final isVertical = pageMode == ReaderPageMode.continuousTopToBottom;
      final isRtl = pageMode == ReaderPageMode.galleryRightToLeft;

      // Right-to-left mode swaps which side is "previous". The user's
      // `readerReverseTapToTurnPages` toggle still applies on top of this
      // so people can further customize their preferred mapping.
      final naturalReverse = isRtl ^ settings.readerReverseTapToTurnPages;
      final tapPrev = naturalReverse ? _goToNextPage : _goToPreviousPage;
      final tapNext = naturalReverse ? _goToPreviousPage : _goToNextPage;

      if (isVertical) {
        final localDy = details.localPosition.dy;
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
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _handleDoubleTap(TapUpDetails details) {
    if (!SettingsController.instance.readerEnableDoubleTapZoom) {
      return;
    }
    _imageKeyFor(
      currentPage - 1,
    ).currentState?.toggleDoubleTapZoom(details.globalPosition);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_isProgressDragging || _controlsVisible) {
      return;
    }
    _longPressStartLocal = details.localPosition;
    _longPressZoomOffset = Offset.zero;
    _longPressDragging = false;
    _isLongPressZooming = true;
    setState(() {});
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isLongPressZooming) return;
    _longPressDragging = true;
    final delta = details.localPosition - _longPressStartLocal;
    _longPressZoomOffset = delta;
    setState(() {});
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _isLongPressZooming = false;
    _longPressDragging = false;
    _longPressZoomOffset = Offset.zero;
    setState(() {});
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
    this.fitWidth = false,
    this.reservedHeight,
    this.onSizeChanged,
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
  final bool fitWidth;
  final double? reservedHeight;
  final ValueChanged<double>? onSizeChanged;
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
        oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.fitWidth != widget.fitWidth) {
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
          return SizedBox(
            height: widget.reservedHeight ?? 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
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
                Text(snapshot.error?.toString() ?? 'Unknown error'),
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

        if (widget.fitWidth) {
          return _MeasuredReaderImage(
            onSizeChanged: widget.onSizeChanged,
            child: Image(
              image: MemoryImage(snapshot.data!),
              width: double.infinity,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
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
    _scale = nextScale;
    _offset = nextOffset;
    _notifyZoomChanged();
    // Defer rebuild to avoid setState inside gesture/mouse-tracker callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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
      final sa = _scaleAnimation;
      final oa = _offsetAnimation;
      if (sa == null || oa == null) return;
      setState(() {
        _scale = sa.value;
        _offset = oa.value;
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

class _MeasuredSize extends StatefulWidget {
  const _MeasuredSize({required this.child, required this.onSizeChanged});

  final Widget child;
  final ValueChanged<Size> onSizeChanged;

  @override
  State<_MeasuredSize> createState() => _MeasuredSizeState();
}

class _MeasuredSizeState extends State<_MeasuredSize> {
  final GlobalKey _key = GlobalKey();
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return KeyedSubtree(key: _key, child: widget.child);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final renderObject = _key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final size = renderObject.size;
      final previous = _lastSize;
      if (previous != null &&
          (previous.width - size.width).abs() < 1 &&
          (previous.height - size.height).abs() < 1) {
        return;
      }
      _lastSize = size;
      widget.onSizeChanged(size);
    });
  }
}

class _MeasuredReaderImage extends StatefulWidget {
  const _MeasuredReaderImage({
    required this.child,
    required this.onSizeChanged,
  });

  final Widget child;
  final ValueChanged<double>? onSizeChanged;

  @override
  State<_MeasuredReaderImage> createState() => _MeasuredReaderImageState();
}

class _MeasuredReaderImageState extends State<_MeasuredReaderImage> {
  final GlobalKey _key = GlobalKey();
  double? _lastHeight;

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return KeyedSubtree(key: _key, child: widget.child);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final renderObject = _key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final height = renderObject.size.height;
      final previous = _lastHeight;
      if (previous != null && (previous - height).abs() < 1) {
        return;
      }
      _lastHeight = height;
      widget.onSizeChanged?.call(height);
    });
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

class _ReaderChapterEndActions extends StatelessWidget {
  const _ReaderChapterEndActions({
    required this.showPrevious,
    required this.showNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool showPrevious;
  final bool showNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final previousLabel = l10n.isChinese ? '上一章' : 'Previous';
    final nextLabel = l10n.isChinese ? '下一章' : 'Next';

    return Row(
      children: [
        if (showPrevious)
          _ReaderChapterEndButton(
            icon: Icons.skip_previous,
            label: previousLabel,
            tooltip: l10n.isChinese ? '上一章' : 'Previous Chapter',
            onPressed: onPrevious,
          ),
        const Spacer(),
        if (showNext)
          _ReaderChapterEndButton(
            icon: Icons.skip_next,
            label: nextLabel,
            tooltip: l10n.isChinese ? '下一章' : 'Next Chapter',
            onPressed: onNext,
            iconAfterLabel: true,
          ),
      ],
    );
  }
}

class _ReaderChapterEndButton extends StatelessWidget {
  const _ReaderChapterEndButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.iconAfterLabel = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool iconAfterLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.primary;
    final iconWidget = Icon(icon, size: 18, color: foreground);
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        elevation: 2,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.18),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40, maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.38),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: iconAfterLabel
                  ? [labelWidget, const SizedBox(width: 6), iconWidget]
                  : [iconWidget, const SizedBox(width: 6), labelWidget],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderCollapsedProgressPill extends StatelessWidget {
  const _ReaderCollapsedProgressPill({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: SizedBox(
        width: 96,
        height: 26,
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                fontWeight: FontWeight.w800,
              ),
            ),
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
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
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
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
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
              onChangeStart: pageCount <= 1 ? null : onChangeStart,
              onChanged: pageCount <= 1 ? null : onChanged,
              onChangeEnd: pageCount <= 1 ? null : onChangeEnd,
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
    required this.volumeKeys,
    required this.horizontalContinuous,
    required this.chapterEdgeButtons,
    required this.onTapToTurnChanged,
    required this.onReverseTapToTurnChanged,
    required this.onDoubleTapZoomChanged,
    required this.onPageAnimationChanged,
    required this.onAutoPageIntervalChanged,
    required this.onPageModeChanged,
    required this.onVolumeKeysChanged,
    required this.onHorizontalContinuousChanged,
    required this.onChapterEdgeButtonsChanged,
  });

  final VoidCallback onClose;
  final bool tapToTurn;
  final bool reverseTapToTurn;
  final bool doubleTapZoom;
  final bool pageAnimation;
  final double autoPageIntervalSeconds;
  final ReaderPageMode pageMode;
  final bool volumeKeys;
  final bool horizontalContinuous;
  final bool chapterEdgeButtons;
  final ValueChanged<bool> onTapToTurnChanged;
  final ValueChanged<bool> onReverseTapToTurnChanged;
  final ValueChanged<bool> onDoubleTapZoomChanged;
  final ValueChanged<bool> onPageAnimationChanged;
  final ValueChanged<double> onAutoPageIntervalChanged;
  final ValueChanged<ReaderPageMode> onPageModeChanged;
  final ValueChanged<bool> onVolumeKeysChanged;
  final ValueChanged<bool> onHorizontalContinuousChanged;
  final ValueChanged<bool> onChapterEdgeButtonsChanged;

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
                      style: ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const Divider(height: 24),
                  if (pageMode != ReaderPageMode.continuousTopToBottom)
                    SwitchListTile(
                      title: Text(l10n.readerHorizontalContinuous),
                      subtitle: Text(l10n.readerHorizontalContinuousSubtitle),
                      value: horizontalContinuous,
                      onChanged: onHorizontalContinuousChanged,
                    ),
                  SwitchListTile(
                    title: Text(l10n.readerTapToTurn),
                    value: tapToTurn,
                    onChanged: onTapToTurnChanged,
                  ),
                  SwitchListTile(
                    title: Text(
                      l10n.isChinese ? '章节首尾按钮' : 'Chapter edge buttons',
                    ),
                    subtitle: Text(
                      l10n.isChinese
                          ? '在章节首页显示上一章，在页尾显示下一章。'
                          : 'Show previous on the first page and next on the last page.',
                    ),
                    value: chapterEdgeButtons,
                    onChanged: onChapterEdgeButtonsChanged,
                  ),
                  if (VolumeListener.isSupported)
                    SwitchListTile(
                      title: Text(l10n.readerVolumeKeys),
                      subtitle: Text(l10n.readerVolumeKeysSubtitle),
                      value: volumeKeys,
                      onChanged: onVolumeKeysChanged,
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
