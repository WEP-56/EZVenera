import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import 'comic_details_page.dart';
import '../state/app_state_controller.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = PluginRuntimeController.instance;
  final appState = AppStateController.instance;
  final keywordController = TextEditingController();

  PluginSource? selectedSource;
  List<PluginComic> results = const <PluginComic>[];
  List<String> optionValues = const <String>[];
  bool isSearching = false;
  String? searchError;
  int currentPage = 1;
  int? maxPage;
  String? nextToken;
  String lastKeyword = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    keywordController.addListener(_onKeywordChanged);
    _syncSelectedSource();
    _restoreState();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    keywordController.removeListener(_onKeywordChanged);
    keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchSources = _searchSources;

    return SafeArea(
      child: ListView(
        key: const PageStorageKey<String>('search-page-list'),
        padding: const EdgeInsets.all(24),
        children: [
          Text('Search', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Search runs directly against installed source plugins. EZVenera currently supports source-driven search options and basic pagination.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (searchSources.isEmpty)
            const _EmptySearchState(
              message:
                  'No searchable sources are installed yet. Add source configs from https://github.com/WEP-56/EZvenera-config first.',
            )
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
            if (results.isNotEmpty) const SizedBox(height: 20),
            ...results.map((comic) => _SearchResultTile(comic: comic)),
            if (results.isNotEmpty) const SizedBox(height: 8),
            if (_canLoadMore)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: isSearching ? null : _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load More'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchForm(BuildContext context, List<PluginSource> sources) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedSource?.key,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Source',
              ),
              items: [
                for (final source in sources)
                  DropdownMenuItem<String>(
                    value: source.key,
                    child: Text(source.name),
                  ),
              ],
              onChanged: isSearching ? null : _changeSource,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keywordController,
              enabled: !isSearching,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Keyword',
                hintText: 'Enter title, tag, or source-specific keyword',
              ),
              onSubmitted: (_) => _search(),
            ),
            if (selectedSource case final source?) ...[
              const SizedBox(height: 16),
              ..._buildOptionWidgets(source),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: isSearching ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: isSearching ? null : _resetResults,
                  child: const Text('Clear Results'),
                ),
              ],
            ),
          ],
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
    final source = selectedSource?.search;
    if (source == null || results.isEmpty || isSearching) {
      return false;
    }
    if (source.loadPage != null) {
      return maxPage != null && currentPage < maxPage!;
    }
    return source.loadNext != null && nextToken != null;
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

    setState(() {
      selectedSource = source;
      optionValues = _defaultOptionsFor(source);
      _resetResultsLocally();
    });
    unawaited(_persistState());
  }

  Future<void> _search() async {
    final source = selectedSource?.search;
    final keyword = keywordController.text.trim();
    if (source == null || keyword.isEmpty) {
      return;
    }

    setState(() {
      isSearching = true;
      searchError = null;
      results = const <PluginComic>[];
      currentPage = 1;
      maxPage = null;
      nextToken = null;
      lastKeyword = keyword;
    });

    try {
      if (source.loadPage != null) {
        final response = await source.loadPage!(keyword, 1, optionValues);
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        setState(() {
          results = response.data;
          maxPage = (response.subData as num?)?.toInt();
          currentPage = 1;
        });
      } else if (source.loadNext != null) {
        final response = await source.loadNext!(keyword, null, optionValues);
        if (response.isError) {
          throw StateError(response.errorMessage!);
        }
        setState(() {
          results = response.data;
          nextToken = response.subData?.toString();
        });
      }
    } catch (error) {
      setState(() {
        searchError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
      unawaited(_persistState());
    }
  }

  Future<void> _loadMore() async {
    final source = selectedSource?.search;
    if (source == null || isSearching) {
      return;
    }

    setState(() {
      isSearching = true;
      searchError = null;
    });

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
      }
    } catch (error) {
      setState(() {
        searchError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
      unawaited(_persistState());
    }
  }

  void _resetResults() {
    setState(() {
      _resetResultsLocally();
      searchError = null;
      keywordController.clear();
      lastKeyword = '';
    });
    unawaited(_persistState());
  }

  void _resetResultsLocally() {
    results = const <PluginComic>[];
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

  void _onKeywordChanged() {
    unawaited(_persistState());
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

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.comic});

  final PluginComic comic;

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
                '${comic.sourceKey} - ${comic.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (comic.tags case final tags? when tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags
                        .take(8)
                        .map((tag) => Chip(label: Text(tag)))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ComicDetailsPage(comic: comic),
            ),
          );
        },
      ),
    );
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
