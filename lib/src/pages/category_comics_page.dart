import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/result.dart';
import '../widgets/comic_card_grid.dart';
import '../widgets/comic_display_toggle.dart';
import 'comic_details_page.dart';

class CategoryComicsPage extends StatefulWidget {
  const CategoryComicsPage({
    required this.source,
    required this.pageTitle,
    this.categoryName,
    this.categoryParam,
    this.searchKeyword,
    this.ranking,
    super.key,
  });

  final PluginSource source;
  final String pageTitle;
  final String? categoryName;
  final String? categoryParam;
  final String? searchKeyword;
  final PluginRankingCapability? ranking;

  @override
  State<CategoryComicsPage> createState() => _CategoryComicsPageState();
}

class _CategoryComicsPageState extends State<CategoryComicsPage> {
  List<PluginCategoryComicsOption> resolvedOptions =
      const <PluginCategoryComicsOption>[];
  List<String> optionValues = const <String>[];
  List<PluginComic> comics = const <PluginComic>[];
  bool isLoading = true;
  bool isLoadingMore = false;
  String? error;
  int currentPage = 1;
  int? maxPage;
  String? nextToken;
  final ScrollController _scrollController = ScrollController();
  bool _optionsVisible = true;
  double _lastScrollOffset = 0;
  static const _scrollThreshold = 40.0;

  bool get isRanking => widget.ranking != null;
  bool get isSearchBridge => widget.searchKeyword != null;

  @override
  void initState() {
    super.initState();
    resolvedOptions = _filteredOptions(widget.source.categoryComics?.options);
    optionValues = _defaultOptions();
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    if (delta > _scrollThreshold && _optionsVisible) {
      setState(() => _optionsVisible = false);
      _lastScrollOffset = offset;
    } else if (delta < -_scrollThreshold && !_optionsVisible) {
      setState(() => _optionsVisible = true);
      _lastScrollOffset = offset;
    } else if (delta.abs() > _scrollThreshold) {
      _lastScrollOffset = offset;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageTitle),
        actions: const [ComicDisplayToggle(dense: true), SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          if (_options.isNotEmpty)
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                heightFactor: _optionsVisible ? 1.0 : 0.0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _optionsVisible ? 1.0 : 0.0,
                  child: _buildOptions(),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<PluginCategoryComicsOption> get _options {
    if (isRanking) {
      return const <PluginCategoryComicsOption>[];
    }
    return resolvedOptions;
  }

  Widget _buildOptions() {
    // Cap the whole filter block so long option lists cannot push the
    // comic grid off-screen. Individual option groups size themselves to
    // content (or paginate) instead of reserving a fixed multi-row height.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.42;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _options.indexed.map((entry) {
            final index = entry.$1;
            final option = entry.$2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PagedCategoryOption(
                option: option,
                selectedValue: optionValues[index],
                pageHeightLimit: maxHeight * 0.55,
                onSelected: (value) {
                  if (optionValues[index] == value) {
                    return;
                  }
                  setState(() {
                    optionValues[index] = value;
                  });
                  _loadPage(1, replace: true);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading && comics.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (error != null && comics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadPage(1, replace: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (comics.isNotEmpty)
          ComicDisplay(
            comics: comics,
            onTap: (comic) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ComicDetailsPage(comic: comic),
                ),
              );
            },
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_canLoadMore)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: isLoading || isLoadingMore
                    ? null
                    : () => _loadPage(currentPage + 1),
                icon: isLoadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(isLoadingMore ? 'Loading...' : 'Load More'),
              ),
            ),
          ),
      ],
    );
  }

  bool get _canLoadMore {
    if (comics.isEmpty) {
      return false;
    }
    if (isRanking) {
      if (widget.ranking?.load != null) {
        return maxPage != null && currentPage < maxPage!;
      }
      return widget.ranking?.loadNext != null && nextToken != null;
    }
    return maxPage != null && currentPage < maxPage!;
  }

  List<String> _defaultOptions() {
    return _options.map((option) => option.options.keys.first).toList();
  }

  Future<void> _initialize() async {
    await _loadDynamicOptions();
    if (!mounted) {
      return;
    }
    await _loadPage(1, replace: true);
  }

  Future<void> _loadDynamicOptions() async {
    if (isRanking || isSearchBridge) {
      return;
    }
    final loader = widget.source.categoryComics?.optionsLoader;
    if (loader == null || widget.categoryName == null) {
      resolvedOptions = _filteredOptions(widget.source.categoryComics?.options);
      optionValues = _defaultOptions();
      return;
    }

    final result = await loader(widget.categoryName!, widget.categoryParam);
    if (!mounted) {
      return;
    }
    if (result.isError) {
      error = result.errorMessage;
      resolvedOptions = _filteredOptions(widget.source.categoryComics?.options);
      optionValues = _defaultOptions();
      return;
    }

    resolvedOptions = _filteredOptions(result.data);
    optionValues = _defaultOptions();
  }

  List<PluginCategoryComicsOption> _filteredOptions(
    List<PluginCategoryComicsOption>? options,
  ) {
    return (options ?? const <PluginCategoryComicsOption>[]).where((option) {
      if (option.options.isEmpty) {
        return false;
      }
      final category = widget.categoryName ?? '';
      if (option.notShowWhen.contains(category)) {
        return false;
      }
      if (option.showWhen != null) {
        return option.showWhen!.contains(category);
      }
      return true;
    }).toList();
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    final preserveScrollOffset = !replace && comics.isNotEmpty;
    final scrollOffset = preserveScrollOffset ? _currentScrollOffset() : 0.0;
    if (preserveScrollOffset) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    setState(() {
      if (preserveScrollOffset) {
        isLoadingMore = true;
      } else {
        isLoading = true;
      }
      if (replace) {
        error = null;
        currentPage = 1;
        maxPage = null;
        nextToken = null;
        isLoadingMore = false;
      }
    });
    if (preserveScrollOffset) {
      _restoreScrollOffset(scrollOffset);
    }

    try {
      final result = isRanking
          ? await _loadRankingPage(page, replace: replace)
          : isSearchBridge
          ? await _loadSearchPage(page)
          : await widget.source.categoryComics!.load(
              widget.categoryName!,
              widget.categoryParam,
              optionValues,
              page,
            );

      if (result.isError) {
        throw StateError(result.errorMessage!);
      }

      final loadedComics = result.data;
      setState(() {
        comics = replace ? loadedComics : [...comics, ...loadedComics];
        if (isRanking && widget.ranking?.loadNext != null) {
          nextToken = result.subData?.toString();
        } else {
          currentPage = page;
          maxPage = (result.subData as num?)?.toInt();
        }
      });
      if (preserveScrollOffset) {
        _restoreScrollOffset(scrollOffset);
      }
    } catch (err) {
      setState(() {
        error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          if (preserveScrollOffset) {
            isLoadingMore = false;
          } else {
            isLoading = false;
          }
        });
        if (preserveScrollOffset) {
          _restoreScrollOffset(scrollOffset);
        }
      }
    }
  }

  double _currentScrollOffset() {
    if (!_scrollController.hasClients) {
      return 0;
    }
    return _scrollController.offset;
  }

  void _restoreScrollOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<PluginResult<List<PluginComic>>> _loadRankingPage(
    int page, {
    required bool replace,
  }) async {
    final ranking = widget.ranking;
    if (ranking == null) {
      return PluginResult<List<PluginComic>>.error('Ranking is not available.');
    }
    final selectedOption = ranking.options.keys.first;
    if (ranking.load != null) {
      return ranking.load!(selectedOption, page);
    }
    if (ranking.loadNext != null) {
      return ranking.loadNext!(selectedOption, replace ? null : nextToken);
    }
    return PluginResult<List<PluginComic>>.error(
      'Ranking does not support pagination.',
    );
  }

  Future<PluginResult<List<PluginComic>>> _loadSearchPage(int page) async {
    final search = widget.source.search;
    if (search == null) {
      return PluginResult<List<PluginComic>>.error(
        'Source does not support search.',
      );
    }
    if (search.loadPage != null) {
      return search.loadPage!(widget.searchKeyword!, page, const <String>[]);
    }
    if (page > 1 || search.loadNext == null) {
      return PluginResult<List<PluginComic>>.error(
        'Search bridge only supports first page for this source.',
      );
    }
    return search.loadNext!(widget.searchKeyword!, null, const <String>[]);
  }
}

class _PagedCategoryOption extends StatefulWidget {
  const _PagedCategoryOption({
    required this.option,
    required this.selectedValue,
    required this.pageHeightLimit,
    required this.onSelected,
  });

  final PluginCategoryComicsOption option;
  final String selectedValue;
  final double pageHeightLimit;
  final ValueChanged<String> onSelected;

  @override
  State<_PagedCategoryOption> createState() => _PagedCategoryOptionState();
}

class _PagedCategoryOptionState extends State<_PagedCategoryOption> {
  int _page = 0;

  static const _chipSpacing = 8.0;
  static const _runSpacing = 8.0;
  // Material 3 FilterChip is taller than the old 32px M2 chip; keep headroom
  // so reserved/estimate heights never clip the bottom of a selected chip.
  static const _chipHeight = 40.0;
  static const _pagerReserve = 44.0;
  static const _headerHeight = 28.0;
  // label padding + selected check icon + chip padding.
  static const _chipHorizontalChrome = 48.0;
  static const _minChipWidth = 56.0;
  // Prefer showing multiple rows of chips per page when tags overflow.
  static const _preferredPageRows = 3;
  static const _maxPageRows = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.option.options.entries.toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final headerHeight =
            widget.option.label.isEmpty ? 0.0 : _headerHeight;
        final textScaler = MediaQuery.textScalerOf(context);
        final textStyle =
            theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14);

        final naturalRows = _estimateWrapRows(
          entries.map((e) => e.value),
          maxWidth: maxWidth,
          textStyle: textStyle,
          textScaler: textScaler,
        );
        final heightBudget = (widget.pageHeightLimit - headerHeight).clamp(
          _chipHeight,
          widget.pageHeightLimit,
        );
        final maxRowsWithoutPager = _rowsForHeight(heightBudget);
        final needsPager = naturalRows > maxRowsWithoutPager;

        // Few tags: size to content — no fixed height, no blank rows.
        if (!needsPager) {
          return _optionColumn(
            theme: theme,
            children: [
              Wrap(
                spacing: _chipSpacing,
                runSpacing: _runSpacing,
                children: [
                  for (final item in entries)
                    _chip(item.key, item.value),
                ],
              ),
            ],
          );
        }

        // Many tags: paginate by chip count, but render each page as a
        // content-sized Wrap (no PageView with a guessed fixed height).
        final rowsPerPage = _rowsForHeight(
          heightBudget - _pagerReserve,
        ).clamp(1, _maxPageRows);
        // Aim for a few rows so long labels don't become 1-chip-per-page.
        final targetRows = rowsPerPage.clamp(1, _preferredPageRows);
        final perPage = _chipsPerPage(
          entries.map((e) => e.value),
          maxWidth: maxWidth,
          maxRows: targetRows < rowsPerPage ? rowsPerPage : targetRows,
          textStyle: textStyle,
          textScaler: textScaler,
        ).clamp(1, entries.length);
        final pages = (entries.length / perPage).ceil();
        final currentPage = _page.clamp(0, pages - 1);
        if (currentPage != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _page != currentPage) {
              setState(() => _page = currentPage);
            }
          });
        }
        final start = currentPage * perPage;
        final end = (start + perPage).clamp(0, entries.length);
        final pageEntries = entries.sublist(start, end);

        return _optionColumn(
          theme: theme,
          children: [
            Wrap(
              spacing: _chipSpacing,
              runSpacing: _runSpacing,
              children: [
                for (final item in pageEntries)
                  _chip(item.key, item.value),
              ],
            ),
            if (pages > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${currentPage + 1}/$pages',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      visualDensity: VisualDensity.compact,
                      onPressed: currentPage <= 0
                          ? null
                          : () => setState(() => _page = currentPage - 1),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous',
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      visualDensity: VisualDensity.compact,
                      onPressed: currentPage >= pages - 1
                          ? null
                          : () => setState(() => _page = currentPage + 1),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _optionColumn({
    required ThemeData theme,
    required List<Widget> children,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.option.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.option.label,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ...children,
      ],
    );
  }

  Widget _chip(String key, String label) {
    return FilterChip(
      selected: widget.selectedValue == key,
      label: Text(label),
      onSelected: (_) => widget.onSelected(key),
    );
  }

  int _rowsForHeight(double height) {
    if (height < _chipHeight) {
      return 1;
    }
    // rows * chipHeight + (rows - 1) * runSpacing <= height
    return ((height + _runSpacing) / (_chipHeight + _runSpacing))
        .floor()
        .clamp(1, _maxPageRows);
  }

  /// Pack as many chips as fit into [maxRows] of a Wrap at [maxWidth].
  int _chipsPerPage(
    Iterable<String> labels, {
    required double maxWidth,
    required int maxRows,
    required TextStyle textStyle,
    required TextScaler textScaler,
  }) {
    if (maxWidth <= 0) {
      return 1;
    }
    var count = 0;
    var rows = 1;
    var x = 0.0;
    for (final label in labels) {
      final chipWidth = _chipWidthFor(
        label,
        textStyle: textStyle,
        textScaler: textScaler,
        maxWidth: maxWidth,
      );
      if (count == 0) {
        count = 1;
        x = chipWidth;
        continue;
      }
      if (x + _chipSpacing + chipWidth <= maxWidth) {
        x += _chipSpacing + chipWidth;
        count++;
        continue;
      }
      if (rows >= maxRows) {
        break;
      }
      rows++;
      x = chipWidth;
      count++;
    }
    return count.clamp(1, 1 << 20);
  }

  int _estimateWrapRows(
    Iterable<String> labels, {
    required double maxWidth,
    required TextStyle textStyle,
    required TextScaler textScaler,
  }) {
    if (maxWidth <= 0) {
      return 1;
    }
    var rows = 1;
    var x = 0.0;
    var first = true;
    for (final label in labels) {
      final chipWidth = _chipWidthFor(
        label,
        textStyle: textStyle,
        textScaler: textScaler,
        maxWidth: maxWidth,
      );
      if (first) {
        x = chipWidth;
        first = false;
        continue;
      }
      if (x + _chipSpacing + chipWidth <= maxWidth) {
        x += _chipSpacing + chipWidth;
      } else {
        rows++;
        x = chipWidth;
      }
    }
    return rows;
  }

  double _chipWidthFor(
    String label, {
    required TextStyle textStyle,
    required TextScaler textScaler,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    // Cap at full row width so a single long label still counts as one chip.
    return (painter.width + _chipHorizontalChrome).clamp(
      _minChipWidth,
      maxWidth,
    );
  }
}
