import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/result.dart';
import '../widgets/comic_card_grid.dart';
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
  late List<String> optionValues = _defaultOptions();
  List<PluginComic> comics = const <PluginComic>[];
  bool isLoading = true;
  String? error;
  int currentPage = 1;
  int? maxPage;

  bool get isRanking => widget.ranking != null;
  bool get isSearchBridge => widget.searchKeyword != null;

  @override
  void initState() {
    super.initState();
    _loadPage(1, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pageTitle)),
      body: Column(
        children: [
          if (_options.isNotEmpty) _buildOptions(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<PluginCategoryComicsOption> get _options {
    if (isRanking) {
      return const <PluginCategoryComicsOption>[];
    }
    return (widget.source.categoryComics?.options ??
            const <PluginCategoryComicsOption>[])
        .where((option) {
          final category = widget.categoryName ?? '';
          if (option.notShowWhen.contains(category)) {
            return false;
          }
          if (option.showWhen != null) {
            return option.showWhen!.contains(category);
          }
          return true;
        })
        .toList();
  }

  Widget _buildOptions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: _options.indexed.map((entry) {
          final index = entry.$1;
          final option = entry.$2;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (option.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      option.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in option.options.entries)
                      FilterChip(
                        selected: optionValues[index] == item.key,
                        label: Text(item.value),
                        onSelected: (_) {
                          if (optionValues[index] == item.key) {
                            return;
                          }
                          setState(() {
                            optionValues[index] = item.key;
                          });
                          _loadPage(1, replace: true);
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
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
      padding: const EdgeInsets.all(16),
      children: [
        if (comics.isNotEmpty)
          ComicCardGrid(
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
                onPressed: isLoading ? null : () => _loadPage(currentPage + 1),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load More'),
              ),
            ),
          ),
      ],
    );
  }

  bool get _canLoadMore => maxPage != null && currentPage < maxPage!;

  List<String> _defaultOptions() {
    return _options.map((option) => option.options.keys.first).toList();
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    setState(() {
      isLoading = true;
      if (replace) {
        error = null;
        currentPage = 1;
        maxPage = null;
      }
    });

    try {
      final result = isRanking
          ? await widget.ranking!.load(
              optionValues.isEmpty
                  ? widget.ranking!.options.keys.first
                  : optionValues.first,
              page,
            )
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
        currentPage = page;
        maxPage = (result.subData as num?)?.toInt();
      });
    } catch (err) {
      setState(() {
        error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
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
