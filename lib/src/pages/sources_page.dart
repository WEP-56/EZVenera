import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';

class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final controller = PluginRuntimeController.instance;
  final urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Sources', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Install source configs from a raw JavaScript URL. Source files should come from https://github.com/WEP-56/EZvenera-config. EZVenera only parses the retained capability set and ignores unsupported fields.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildInstallCard(context),
          const SizedBox(height: 20),
          if (controller.isBusy) const LinearProgressIndicator(),
          if (controller.errorMessage case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (controller.sources.isEmpty)
            _buildEmptyState(context)
          else
            ...controller.sources.map((source) => _SourceCard(source: source)),
        ],
      ),
    );
  }

  Widget _buildInstallCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Install Source',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              enabled: !controller.isBusy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Source URL',
                hintText: 'https://example.com/source.js',
              ),
              onSubmitted: (_) => _installFromUrl(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: controller.isBusy ? null : _installFromUrl,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _reloadSources,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
          Text('No sources installed', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Install a source config first. Existing Venera source files are supported as long as they stay within the retained EZVenera capability set.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installFromUrl() async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    try {
      final source = await controller.installFromUrl(url);
      if (!mounted) {
        return;
      }
      urlController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Installed ${source.name}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to install source')));
    }
  }

  Future<void> _reloadSources() async {
    try {
      await controller.reload();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sources reloaded')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to reload sources')));
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final PluginSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${source.key}  ·  v${source.version}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, source),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _capabilities(source).map((label) {
                return Chip(label: Text(label));
              }).toList(),
            ),
            const SizedBox(height: 16),
            SelectableText(
              source.filePath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _capabilities(PluginSource source) {
    final labels = <String>[];
    if (source.account != null) labels.add('account');
    if (source.search != null) labels.add('search');
    if (source.category != null) labels.add('category');
    if (source.categoryComics != null) labels.add('categoryComics');
    if (source.comic != null) labels.add('comic');
    if (source.comic?.onImageLoad != null) labels.add('onImageLoad');
    if (source.comic?.onThumbnailLoad != null) labels.add('onThumbnailLoad');
    if (source.settings.isNotEmpty) labels.add('settings');
    if (source.link != null) labels.add('link');
    if (source.idMatcher != null) labels.add('idMatch');
    return labels;
  }

  Future<void> _confirmDelete(BuildContext context, PluginSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Source'),
          content: Text('Delete ${source.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await PluginRuntimeController.instance.removeSource(source);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted ${source.name}')));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete source')));
    }
  }
}
