import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../state/app_state_controller.dart';
import 'category_comics_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with TickerProviderStateMixin {
  TabController? _controller;

  List<PluginSource> get _sources {
    return PluginRuntimeController.instance.sources
        .where((source) => source.category != null)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    PluginRuntimeController.instance.addListener(_onSourcesChanged);
    _resetController();
  }

  @override
  void dispose() {
    PluginRuntimeController.instance.removeListener(_onSourcesChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = _sources;

    if (sources.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              'No category-enabled sources installed yet.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _controller,
              isScrollable: true,
              tabs: [
                for (final source in sources)
                  Tab(
                    text: source.category!.title.isEmpty
                        ? source.name
                        : source.category!.title,
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: [
                for (final source in sources)
                  _CategorySourcePage(source: source),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSourcesChanged() {
    if (mounted) {
      setState(_resetController);
    }
  }

  void _resetController() {
    final sources = _sources;
    _controller?.removeListener(_onTabChanged);
    _controller?.dispose();
    final length = math.max(1, sources.length);
    final restoredKey = AppStateController.instance.getString(
      'categories.selectedSourceKey',
    );
    var initialIndex = 0;
    if (restoredKey != null && sources.isNotEmpty) {
      final restoredIndex = sources.indexWhere(
        (source) => source.key == restoredKey,
      );
      if (restoredIndex >= 0) {
        initialIndex = restoredIndex;
      }
    }
    _controller = TabController(
      length: length,
      vsync: this,
      initialIndex: sources.isEmpty ? 0 : initialIndex,
    );
    _controller!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final controller = _controller;
    final sources = _sources;
    if (controller == null ||
        controller.indexIsChanging ||
        sources.isEmpty ||
        controller.index >= sources.length) {
      return;
    }
    unawaited(
      AppStateController.instance.setString(
        'categories.selectedSourceKey',
        sources[controller.index].key,
      ),
    );
  }
}

class _CategorySourcePage extends StatelessWidget {
  const _CategorySourcePage({required this.source});

  final PluginSource source;

  PluginCategoryCapability get category => source.category!;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (category.enableRankingPage) {
      children.add(
        _PartSection(
          title: 'Actions',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  if (source.categoryComics?.ranking == null) {
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => CategoryComicsPage(
                        source: source,
                        pageTitle: '${source.name} Ranking',
                        ranking: source.categoryComics!.ranking,
                      ),
                    ),
                  );
                },
                child: const Text('Ranking'),
              ),
            ],
          ),
        ),
      );
    }

    for (final part in category.parts) {
      final items = part.type == PluginCategoryPartType.dynamic
          ? (part.dynamicLoader?.call() ?? const <PluginCategoryItem>[])
          : part.type == PluginCategoryPartType.random
          ? _randomItems(part.items, part.randomNumber ?? 1)
          : part.items;

      children.add(
        _PartSection(
          title: part.name,
          trailing: part.type == PluginCategoryPartType.random
              ? Builder(
                  builder: (context) {
                    return IconButton(
                      onPressed: () {
                        (context as Element).markNeedsBuild();
                      },
                      icon: const Icon(Icons.refresh),
                    );
                  },
                )
              : null,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ActionChip(
                  label: Text(item.label),
                  onPressed: () => _openTarget(context, source, item.target),
                ),
            ],
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(24), children: children);
  }

  List<PluginCategoryItem> _randomItems(
    List<PluginCategoryItem> items,
    int randomNumber,
  ) {
    if (randomNumber >= items.length) {
      return items;
    }
    final start = math.Random().nextInt(items.length - randomNumber);
    return items.sublist(start, start + randomNumber);
  }

  void _openTarget(
    BuildContext context,
    PluginSource source,
    PluginJumpTarget target,
  ) {
    if (target.page == 'category') {
      if (source.categoryComics == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CategoryComicsPage(
            source: source,
            pageTitle:
                target.attributes?['category']?.toString() ?? source.name,
            categoryName: target.attributes?['category']?.toString() ?? '',
            categoryParam: target.attributes?['param']?.toString(),
          ),
        ),
      );
      return;
    }

    if (target.page == 'search') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CategoryComicsSearchBridgePage(
            source: source,
            keyword: target.attributes?['keyword']?.toString() ?? '',
          ),
        ),
      );
    }
  }
}

class _PartSection extends StatelessWidget {
  const _PartSection({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in [trailing].whereType<Widget>()) item,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class CategoryComicsSearchBridgePage extends StatelessWidget {
  const CategoryComicsSearchBridgePage({
    required this.source,
    required this.keyword,
    super.key,
  });

  final PluginSource source;
  final String keyword;

  @override
  Widget build(BuildContext context) {
    return CategoryComicsPage(
      source: source,
      pageTitle: keyword,
      searchKeyword: keyword,
    );
  }
}
