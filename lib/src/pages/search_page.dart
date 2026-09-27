import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../plugin_runtime/result.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import '../settings/settings_controller.dart';
import '../state/app_state_controller.dart';
import '../widgets/comic_card_grid.dart';
import '../widgets/comic_display_toggle.dart';
import 'comic_details_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const aggregateSourceTimeout = Duration(seconds: 20);

  final controller = PluginRuntimeController.instance;
  final appState = AppStateController.instance;
  final keywordController = TextEditingController();
  final keywordFocusNode = FocusNode();
  final scrollController = ScrollController();

  PluginSource? selectedSource;
  List<PluginComic> results = const <PluginComic>[];
  List<String> optionValues = const <String>[];
  List<_AggregateSearchResult> aggregateResults =
      const <_AggregateSearchResult>[];
  bool isSearching = false;
  bool isLoadingMore = false;
  String? searchError;
  int currentPage = 1;
  int? maxPage;
  String? nextToken;
  String lastKeyword = '';
  bool searchFormExpanded = false;
  bool aggregatedSearch = false;
  int searchRun = 0;
  List<String> searchHistory = const <String>[];
  bool searchHistoryPointerActive = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    SettingsController.instance.addListener(_onSettingsChanged);
    keywordController.addListener(_onKeywordChanged);
    keywordFocusNode.addListener(_onKeywordFocusChanged);
    _syncSelectedSource();
    _restoreSearchHistory();
    _restoreState();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    SettingsController.instance.removeListener(_onSettingsChanged);
    keywordController.removeListener(_onKeywordChanged);
    keywordFocusNode.removeListener(_onKeywordFocusChanged);
    keywordController.dispose();
    keywordFocusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final searchSources = _searchSources;

    return SafeArea(
      child: ListView(
        key: const PageStorageKey<String>('search-page-list'),
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          if (searchSources.isEmpty)
            _EmptySearchState(message: l10n.searchNoSearchableSources)
          else ...[
            _buildSearchForm(context, searchSources),
            const SizedBox(height: 20),
            if (isSearching) const LinearProgressIndicator(),
            if (searchError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_hasSearchResults) const SizedBox(height: 20),
            if (!aggregatedSearch && results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: const ComicDisplayToggle(dense: true),
                ),
              ),
            if (aggregatedSearch && aggregateResults.isNotEmpty)
              _AggregateSearchResultsView(
                results: aggregateResults,
                onTap: _openComic,
              )
            else if (results.isNotEmpty)
              ComicDisplay(comics: results, onTap: _openComic),
            if (_hasSearchResults) const SizedBox(height: 8),
            if (_canLoadMore)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: isSearching || isLoadingMore ? null : _loadMore,
                  icon: isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(isLoadingMore ? 'Loading...' : 'Load More'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchForm(BuildContext context, List<PluginSource> sources) {
    final l10n = AppLocalizations.of(context);

    return TapRegion(
      onTapOutside: (_) {
        keywordFocusNode.unfocus();
      },
      child: Card(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            searchFormExpanded ? 20 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnimatedSearchSection(
                expanded: searchFormExpanded,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.searchAggregate),
                      subtitle: Text(l10n.searchAggregateSubtitle),
                      value: aggregatedSearch,
                      onChanged: (value) {
                        _setSearchFormExpanded(true);
                        searchRun++;
                        setState(() {
                          isSearching = false;
                          isLoadingMore = false;
                          aggregatedSearch = value;
                          _resetResultsLocally();
                          searchError = null;
                        });
                        unawaited(_persistState());
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!aggregatedSearch) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedSource?.key,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: l10n.searchSource,
                        ),
                        items: [
                          for (final source in sources)
                            DropdownMenuItem<String>(
                              value: source.key,
                              child: Text(source.name),
                            ),
                        ],
                        onChanged: (value) {
                          _setSearchFormExpanded(true);
                          _changeSource(value);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              TextField(
                controller: keywordController,
                focusNode: keywordFocusNode,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.searchKeyword,
                  hintText: l10n.searchKeywordHint,
                  suffixIcon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: IconButton(
                      key: ValueKey(searchFormExpanded),
                      icon: Icon(
                        searchFormExpanded
                            ? Icons.unfold_less
                            : Icons.unfold_more,
                      ),
                      onPressed: () {
                        _setSearchFormExpanded(!searchFormExpanded);
                      },
                    ),
                  ),
                ),
                onTap: () => _setSearchFormExpanded(true),
                onSubmitted: (_) => _search(),
              ),
              if (_shouldShowSearchHistory)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _SearchHistoryDropdown(
                    items: searchHistory,
                    onPointerActiveChanged: _setSearchHistoryPointerActive,
                    onSelected: _selectSearchHistory,
                  ),
                ),
              _AnimatedSearchSection(
                expanded: searchFormExpanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!aggregatedSearch && selectedSource != null) ...[
                      const SizedBox(height: 16),
                      ..._buildOptionWidgets(selectedSource!),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _search,
                          icon: const Icon(Icons.search),
                          label: Text(l10n.searchSearch),
                        ),
                        OutlinedButton(
                          onPressed: _resetResults,
                          child: Text(l10n.searchClearResults),
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
    );
  }

  List<Widget> _buildOptionWidgets(PluginSource source) {
    final search = source.search;
    if (search == null || search.options.isEmpty) {
      return const <Widget>[];
    }

    return search.options.indexed.map((entry) {
      final index = entry.$1;
      final option = entry.$2;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _SearchOptionField(
          option: option,
          value: optionValues[index],
          onChanged: (value) {
            setState(() {
              final nextValues = List<String>.from(optionValues);
              nextValues[index] = value;
              optionValues = nextValues;
            });
            unawaited(_persistState());
          },
        ),
      );
    }).toList();
  }

  List<PluginSource> get _searchSources {
    return controller.sources.where((source) => source.search != null).toList();
  }

  bool get _canLoadMore {
    if (aggregatedSearch) {
      return false;
    }
    final source = selectedSource?.search;
    if (source == null || results.isEmpty) {
      return false;
    }
    if (source.loadPage != null) {
      return maxPage != null && currentPage < maxPage!;
    }
    return source.loadNext != null && nextToken != null;
  }

  bool get _shouldShowSearchHistory {
    return (keywordFocusNode.hasFocus || searchHistoryPointerActive) &&
        searchHistory.isNotEmpty &&
        SettingsController.instance.searchHistoryLimit > 0;
  }

  void _changeSource(String? sourceKey) {
    if (sourceKey == null) {
      return;
    }

    final source = controller.sources
        .where((item) => item.key == sourceKey)
        .firstOrNull;
    if (source == null) {
      return;
    }

    searchRun++;
    setState(() {
      isSearching = false;
      selectedSource = source;
      optionValues = _defaultOptionsFor(source);
      _resetResultsLocally();
    });
    unawaited(_persistState());
  }

  Future<void> _search() async {
    final l10n = AppLocalizations.of(context);
    final keyword = keywordController.text.trim();
    if (keyword.isEmpty) {
      searchRun++;
      setState(() {
        isSearching = false;
        isLoadingMore = false;
        searchError = null;
        _resetResultsLocally();
      });
      unawaited(_persistState());
      return;
    }

    await _rememberSearchKeyword(keyword);
    final run = ++searchRun;
    if (aggregatedSearch) {
      await _searchAggregated(run, keyword);
      return;
    }

    final source = selectedSource?.search;
    if (source == null) {
      setState(() {
        isSearching = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
      isLoadingMore = false;
      searchError = null;
      results = const <PluginComic>[];
      aggregateResults = const <_AggregateSearchResult>[];
      currentPage = 1;
      maxPage = null;
      nextToken = null;
      lastKeyword = keyword;
    });

    try {
      if (source.loadPage != null) {
        final response = await source.loadPage!(keyword, 1, optionValues)
            .timeout(
              aggregateSourceTimeout,
              onTimeout: () => throw TimeoutException(l10n.searchTimeout),
            );
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        if (!mounted || run != searchRun) {
          return;
        }
        setState(() {
          results = response.data;
          maxPage = (response.subData as num?)?.toInt();
          currentPage = 1;
        });
      } else if (source.loadNext != null) {
        final response = await source.loadNext!(keyword, null, optionValues)
            .timeout(
              aggregateSourceTimeout,
              onTimeout: () => throw TimeoutException(l10n.searchTimeout),
            );
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        if (!mounted || run != searchRun) {
          return;
        }
        setState(() {
          results = response.data;
          nextToken = response.subData?.toString();
        });
      }
    } catch (error) {
      if (!mounted || run != searchRun) {
        return;
      }
      setState(() {
        searchError = _searchErrorMessage(error, l10n);
      });
    } finally {
      if (mounted && run == searchRun) {
        setState(() {
          isSearching = false;
        });
      }
      unawaited(_persistState());
    }
  }

  Future<void> _searchAggregated(int run, String keyword) async {
    final l10n = AppLocalizations.of(context);
    final sources = _searchSources;
    if (sources.isEmpty) {
      setState(() {
        isSearching = false;
        isLoadingMore = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
      isLoadingMore = false;
      searchError = null;
      results = const <PluginComic>[];
      aggregateResults = [
        for (final source in sources)
          _AggregateSearchResult.loading(source: source),
      ];
      currentPage = 1;
      maxPage = null;
      nextToken = null;
      lastKeyword = keyword;
    });

    await Future.wait(
      sources.indexed.map((entry) async {
        final index = entry.$1;
        final source = entry.$2;
        final search = source.search;
        if (search == null) {
          return;
        }

        // Stagger the fan-out: all sources dialing the same proxy/network in
        // the same instant makes every concurrent TLS handshake compete, and
        // one transient blip then kills the whole batch at once (observed on
        // a device behind a LAN proxy). Sequential flows like category
        // browsing never hit this, which made search look "broken" while
        // everything else worked. A small per-source delay keeps the burst
        // gentle; total wall time is unaffected because requests still run
        // concurrently after the stagger.
        if (index > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 120 * index.clamp(0, 20)),
          );
        }

        try {
          final response = await _runSearchRequest(search, keyword, source, l10n);
          if (response.isError) {
            throw StateError(response.errorMessage ?? 'Unknown error');
          }
          _updateAggregateResult(
            run: run,
            index: index,
            next: _AggregateSearchResult.loaded(
              source: source,
              comics: response.data,
            ),
          );
        } catch (error) {
          // One bounded retry with a short backoff: a transient handshake /
          // proxy blip should not surface as a permanent error card when a
          // single immediate re-attempt succeeds (category requests, being
          // one-off and sequential, effectively never see this).
          try {
            await Future<void>.delayed(const Duration(seconds: 2));
            final retried = await _runSearchRequest(
              search,
              keyword,
              source,
              l10n,
            );
            if (retried.isError) {
              throw StateError(retried.errorMessage ?? 'Unknown error');
            }
            if (!mounted || run != searchRun) {
              return;
            }
            _updateAggregateResult(
              run: run,
              index: index,
              next: _AggregateSearchResult.loaded(
                source: source,
                comics: retried.data,
              ),
            );
          } catch (retryError) {
            if (!mounted || run != searchRun) {
              return;
            }
            _updateAggregateResult(
              run: run,
              index: index,
              next: _AggregateSearchResult.error(
                source: source,
                error: _searchErrorMessage(retryError, l10n),
              ),
            );
          }
        }
      }),
    );

    if (!mounted || run != searchRun) {
      return;
    }
    setState(() {
      isSearching = false;
    });
    unawaited(_persistState());
  }

  /// Runs one search request against [search] with the aggregate timeout
  /// applied. Kept separate so the stagger/retry policy in
  /// [_searchAggregated] stays readable.
  Future<PluginResult<List<PluginComic>>> _runSearchRequest(
    PluginSearchCapability search,
    String keyword,
    PluginSource source,
    AppLocalizations l10n,
  ) {
    final response = switch (search) {
      PluginSearchCapability(loadPage: final loadPage?) =>
        loadPage(keyword, 1, _defaultOptionsFor(source)),
      PluginSearchCapability(loadNext: final loadNext?) =>
        loadNext(keyword, null, _defaultOptionsFor(source)),
      _ => throw StateError(l10n.searchLoaderMissing),
    };
    return response.timeout(
      aggregateSourceTimeout,
      onTimeout: () => throw TimeoutException(l10n.searchTimeout),
    );
  }

  void _updateAggregateResult({
    required int run,
    required int index,
    required _AggregateSearchResult next,
  }) {
    if (!mounted || run != searchRun) {
      return;
    }
    setState(() {
      final updated = List<_AggregateSearchResult>.from(aggregateResults);
      if (index >= 0 && index < updated.length) {
        updated[index] = next;
        aggregateResults = updated;
      }
    });
  }

  Future<void> _loadMore() async {
    final source = selectedSource?.search;
    if (source == null || isSearching || isLoadingMore) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final scrollOffset = _currentScrollOffset();
    setState(() {
      isLoadingMore = true;
      searchError = null;
    });
    _restoreScrollOffset(scrollOffset);

    try {
      if (source.loadPage != null) {
        final nextPage = currentPage + 1;
        final response = await source.loadPage!(
          lastKeyword,
          nextPage,
          optionValues,
        );
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        setState(() {
          results = [...results, ...response.data];
          currentPage = nextPage;
          maxPage = (response.subData as num?)?.toInt() ?? maxPage;
        });
        _restoreScrollOffset(scrollOffset);
      } else if (source.loadNext != null) {
        final response = await source.loadNext!(
          lastKeyword,
          nextToken,
          optionValues,
        );
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        setState(() {
          results = [...results, ...response.data];
          nextToken = response.subData?.toString();
        });
        _restoreScrollOffset(scrollOffset);
      }
    } catch (error) {
      setState(() {
        searchError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoadingMore = false;
        });
        _restoreScrollOffset(scrollOffset);
      }
      unawaited(_persistState());
    }
  }

  double _currentScrollOffset() {
    if (!scrollController.hasClients) {
      return 0;
    }
    return scrollController.offset;
  }

  void _restoreScrollOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      final target = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() > 0.5) {
        scrollController.jumpTo(target);
      }
    });
  }

  void _resetResults() {
    searchRun++;
    setState(() {
      isSearching = false;
      isLoadingMore = false;
      _resetResultsLocally();
      searchError = null;
      keywordController.clear();
      lastKeyword = '';
    });
    unawaited(_persistState());
  }

  void _resetResultsLocally() {
    results = const <PluginComic>[];
    aggregateResults = const <_AggregateSearchResult>[];
    isLoadingMore = false;
    currentPage = 1;
    maxPage = null;
    nextToken = null;
  }

  void _syncSelectedSource() {
    final searchSources = _searchSources;
    if (searchSources.isEmpty) {
      selectedSource = null;
      optionValues = const <String>[];
      return;
    }

    final currentKey = selectedSource?.key;
    final stillExists = currentKey == null
        ? null
        : searchSources.where((source) => source.key == currentKey).firstOrNull;
    final source = stillExists ?? searchSources.first;

    selectedSource = source;
    optionValues = _normalizeOptionValues(source, optionValues);
  }

  void _restoreState() {
    final state = appState.getSection('search.page');
    if (state.isEmpty) {
      return;
    }

    final sourceKey = state['selectedSourceKey']?.toString();
    var restoredSourceMissing = false;
    if (sourceKey != null) {
      selectedSource = _searchSources
          .where((source) => source.key == sourceKey)
          .firstOrNull;
      restoredSourceMissing = selectedSource == null;
    }
    selectedSource ??= _searchSources.firstOrNull;
    if (selectedSource != null) {
      optionValues = _normalizeOptionValues(
        selectedSource!,
        List<String>.from(state['optionValues'] ?? const <String>[]),
      );
    }

    keywordController.text = state['keyword']?.toString() ?? '';
    lastKeyword = state['lastKeyword']?.toString() ?? keywordController.text;
    aggregatedSearch = state['aggregatedSearch'] == true;
    currentPage = (state['currentPage'] as num?)?.toInt() ?? 1;
    maxPage = (state['maxPage'] as num?)?.toInt();
    nextToken = state['nextToken']?.toString();
    searchError = state['searchError']?.toString();
    results = restoredSourceMissing
        ? const <PluginComic>[]
        : (state['results'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => _comicFromJson(Map<String, dynamic>.from(item)))
              .toList();
  }

  void _restoreSearchHistory() {
    final section = appState.getSection('search.history');
    searchHistory = (section['items'] as List? ?? const <dynamic>[])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    searchHistory = _trimSearchHistory(searchHistory);
  }

  Future<void> _rememberSearchKeyword(String keyword) async {
    final normalized = keyword.trim();
    final limit = SettingsController.instance.searchHistoryLimit;
    if (normalized.isEmpty || limit <= 0) {
      return;
    }

    final updated = <String>[
      normalized,
      ...searchHistory.where((item) => item != normalized),
    ];
    final trimmed = _trimSearchHistory(updated);
    setState(() {
      searchHistory = trimmed;
    });
    await appState.setSection('search.history', <String, dynamic>{
      'items': trimmed,
    });
  }

  List<String> _trimSearchHistory(List<String> items) {
    final limit = SettingsController.instance.searchHistoryLimit;
    if (limit <= 0) {
      return const <String>[];
    }
    return items.take(limit).toList();
  }

  void _selectSearchHistory(String keyword) {
    setState(() {
      searchHistoryPointerActive = false;
      keywordController.text = keyword;
      keywordController.selection = TextSelection.collapsed(
        offset: keyword.length,
      );
    });
    keywordFocusNode.unfocus();
    unawaited(_search());
  }

  void _setSearchHistoryPointerActive(bool value) {
    if (searchHistoryPointerActive == value) {
      return;
    }
    setState(() {
      searchHistoryPointerActive = value;
    });
  }

  List<String> _normalizeOptionValues(
    PluginSource source,
    List<String> candidateValues,
  ) {
    final defaults = _defaultOptionsFor(source);
    if (candidateValues.length != defaults.length) {
      return defaults;
    }
    return candidateValues;
  }

  Future<void> _persistState() {
    return appState.setSection('search.page', <String, dynamic>{
      'selectedSourceKey': selectedSource?.key,
      'aggregatedSearch': aggregatedSearch,
      'keyword': keywordController.text,
      'lastKeyword': lastKeyword,
      'optionValues': optionValues,
      'currentPage': currentPage,
      'maxPage': maxPage,
      'nextToken': nextToken,
      'searchError': searchError,
      'results': results.map(_comicToJson).toList(),
    });
  }

  Map<String, dynamic> _comicToJson(PluginComic comic) {
    return <String, dynamic>{
      'id': comic.id,
      'title': comic.title,
      'cover': comic.cover,
      'sourceKey': comic.sourceKey,
      'subtitle': comic.subtitle,
      'tags': comic.tags,
      'description': comic.description,
      'maxPage': comic.maxPage,
      'language': comic.language,
      'favoriteId': comic.favoriteId,
      'stars': comic.stars,
    };
  }

  PluginComic _comicFromJson(Map<String, dynamic> json) {
    return PluginComic(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      sourceKey: json['sourceKey']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      tags: List<String>.from(json['tags'] ?? const <String>[]),
      description: json['description']?.toString() ?? '',
      maxPage: (json['maxPage'] as num?)?.toInt(),
      language: json['language']?.toString(),
      favoriteId: json['favoriteId']?.toString(),
      stars: (json['stars'] as num?)?.toDouble(),
    );
  }

  List<String> _defaultOptionsFor(PluginSource source) {
    final options = source.search?.options ?? const <PluginSearchOption>[];
    return options.map((option) {
      if (option.defaultValue != null) {
        return option.defaultValue!;
      }
      if (option.type == 'multi-select') {
        return '[]';
      }
      return option.options.keys.firstOrNull ?? '';
    }).toList();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      final previousKey = selectedSource?.key;
      _syncSelectedSource();
      if (selectedSource?.key != previousKey) {
        _resetResultsLocally();
      }
    });
    unawaited(_persistState());
  }

  void _onSettingsChanged() {
    final trimmed = _trimSearchHistory(searchHistory);
    if (trimmed.length == searchHistory.length) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    searchHistory = trimmed;
    unawaited(
      appState.setSection('search.history', <String, dynamic>{
        'items': trimmed,
      }),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _onKeywordChanged() {
    unawaited(_persistState());
  }

  void _onKeywordFocusChanged() {
    if (keywordFocusNode.hasFocus) {
      _setSearchFormExpanded(true);
      if (mounted) {
        setState(() {});
      }
    } else if (mounted && !searchHistoryPointerActive) {
      setState(() {});
    }
  }

  void _setSearchFormExpanded(bool value) {
    if (searchFormExpanded == value) {
      return;
    }
    setState(() {
      searchFormExpanded = value;
    });
  }

  bool get _hasSearchResults {
    return aggregatedSearch ? aggregateResults.isNotEmpty : results.isNotEmpty;
  }

  void _openComic(PluginComic comic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComicDetailsPage(comic: comic),
      ),
    );
  }

  String _searchErrorMessage(Object error, AppLocalizations l10n) {
    if (error is TimeoutException) {
      return error.message ?? l10n.searchTimeout;
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }
}

class _AggregateSearchResult {
  const _AggregateSearchResult({
    required this.source,
    required this.comics,
    required this.isLoading,
    this.error,
  });

  factory _AggregateSearchResult.loading({required PluginSource source}) {
    return _AggregateSearchResult(
      source: source,
      comics: const <PluginComic>[],
      isLoading: true,
    );
  }

  factory _AggregateSearchResult.loaded({
    required PluginSource source,
    required List<PluginComic> comics,
  }) {
    return _AggregateSearchResult(
      source: source,
      comics: comics,
      isLoading: false,
    );
  }

  factory _AggregateSearchResult.error({
    required PluginSource source,
    required String error,
  }) {
    return _AggregateSearchResult(
      source: source,
      comics: const <PluginComic>[],
      isLoading: false,
      error: error,
    );
  }

  final PluginSource source;
  final List<PluginComic> comics;
  final bool isLoading;
  final String? error;
}

class _AggregateSearchResultsView extends StatelessWidget {
  const _AggregateSearchResultsView({
    required this.results,
    required this.onTap,
  });

  static const double _coverWidth = 98;
  static const double _coverHeight = 136;
  static const double _tileWidth = 112;
  static const double _rowHeight = 170;

  final List<_AggregateSearchResult> results;
  final ValueChanged<PluginComic> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final result in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: _AggregateSourceSection(result: result, onTap: onTap),
          ),
      ],
    );
  }
}

class _AggregateSourceSection extends StatefulWidget {
  const _AggregateSourceSection({required this.result, required this.onTap});

  final _AggregateSearchResult result;
  final ValueChanged<PluginComic> onTap;

  @override
  State<_AggregateSourceSection> createState() =>
      _AggregateSourceSectionState();
}

class _AggregateSourceSectionState extends State<_AggregateSourceSection> {
  final scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.result.source.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        if (widget.result.isLoading)
          const _AggregateLoadingRow()
        else if (widget.result.error != null || widget.result.comics.isEmpty)
          _AggregateEmptyRow(
            message: widget.result.error ?? l10n.searchNoResults,
          )
        else
          SizedBox(
            height: _AggregateSearchResultsView._rowHeight + 16,
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView.separated(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: widget.result.comics.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final comic = widget.result.comics[index];
                  return _AggregateComicTile(
                    comic: comic,
                    onTap: () => widget.onTap(comic),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _AggregateLoadingRow extends StatelessWidget {
  const _AggregateLoadingRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _AggregateSearchResultsView._rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return Column(
            children: [
              Container(
                width: _AggregateSearchResultsView._coverWidth,
                height: _AggregateSearchResultsView._coverHeight,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.52,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 82,
                height: 12,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.48,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AggregateEmptyRow extends StatelessWidget {
  const _AggregateEmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _AggregateSearchResultsView._rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregateComicTile extends StatelessWidget {
  const _AggregateComicTile({required this.comic, required this.onTap});

  final PluginComic comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: _AggregateSearchResultsView._tileWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _AggregateSearchResultsView._coverWidth,
              height: _AggregateSearchResultsView._coverHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _AggregateComicCover(
                  sourceKey: comic.sourceKey,
                  imageUrl: comic.cover,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: _AggregateSearchResultsView._coverWidth,
              child: Text(
                comic.title.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AggregateComicCover extends StatefulWidget {
  const _AggregateComicCover({required this.sourceKey, required this.imageUrl});

  final String sourceKey;
  final String imageUrl;

  @override
  State<_AggregateComicCover> createState() => _AggregateComicCoverState();
}

class _AggregateComicCoverState extends State<_AggregateComicCover> {
  static final Map<String, Future<Uint8List>> _thumbnailCache =
      <String, Future<Uint8List>>{};

  late Future<Uint8List> imageFuture;

  @override
  void initState() {
    super.initState();
    imageFuture = _loadImage();
  }

  @override
  void didUpdateWidget(covariant _AggregateComicCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.imageUrl != widget.imageUrl) {
      imageFuture = _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: widget.imageUrl.trim().isEmpty
          ? const _AggregateCoverFallback(icon: Icons.image_not_supported)
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
                      return const _AggregateCoverFallback(
                        icon: Icons.broken_image_outlined,
                      );
                    },
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

class _AggregateCoverFallback extends StatelessWidget {
  const _AggregateCoverFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        size: 32,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SearchHistoryDropdown extends StatefulWidget {
  const _SearchHistoryDropdown({
    required this.items,
    required this.onPointerActiveChanged,
    required this.onSelected,
  });

  final List<String> items;
  final ValueChanged<bool> onPointerActiveChanged;
  final ValueChanged<String> onSelected;

  @override
  State<_SearchHistoryDropdown> createState() => _SearchHistoryDropdownState();
}

class _SearchHistoryDropdownState extends State<_SearchHistoryDropdown> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleRows = widget.items.length.clamp(1, 5);
    const rowHeight = 44.0;

    return Listener(
      onPointerDown: (_) => widget.onPointerActiveChanged(true),
      onPointerUp: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onPointerActiveChanged(false);
        });
      },
      onPointerCancel: (_) => widget.onPointerActiveChanged(false),
      child: Container(
        height: visibleRows * rowHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.72,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: widget.items.length > 5,
          child: ListView.builder(
            controller: _controller,
            padding: EdgeInsets.zero,
            itemExtent: rowHeight,
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return InkWell(
                onTap: () => widget.onSelected(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.north_west,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SearchOptionField extends StatelessWidget {
  const _SearchOptionField({
    required this.option,
    required this.value,
    required this.onChanged,
  });

  final PluginSearchOption option;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option.label.isEmpty ? 'Option' : option.label,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (option.type == 'dropdown')
          DropdownButtonFormField<String>(
            initialValue: option.options.containsKey(value) ? value : null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final entry in option.options.entries)
                DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in option.options.entries)
                FilterChip(
                  selected: _isSelected(entry.key),
                  label: Text(entry.value),
                  onSelected: (_) => _toggle(entry.key),
                ),
            ],
          ),
      ],
    );
  }

  bool _isSelected(String key) {
    if (option.type == 'multi-select') {
      final values = (jsonDecode(value) as List).cast<String>();
      return values.contains(key);
    }
    return value == key;
  }

  void _toggle(String key) {
    if (option.type == 'multi-select') {
      final values = (jsonDecode(value) as List).cast<String>().toList();
      if (values.contains(key)) {
        values.remove(key);
      } else {
        values.add(key);
      }
      onChanged(jsonEncode(values));
      return;
    }
    onChanged(key);
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.message});

  final String message;

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
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}

class _AnimatedSearchSection extends StatelessWidget {
  const _AnimatedSearchSection({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: expanded ? 1 : 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          opacity: expanded ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
