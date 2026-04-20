import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../settings/settings_controller.dart';

class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final controller = PluginRuntimeController.instance;
  final settings = SettingsController.instance;
  final urlController = TextEditingController();
  final dio = Dio(
    BaseOptions(responseType: ResponseType.plain, validateStatus: (_) => true),
  );

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
          Text('Comic Source', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'EZVenera keeps the original source-management pattern: add sources from URL or repository index, then manage each source individually.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _buildAddSourceCard(context),
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

  Widget _buildAddSourceCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.extension_outlined),
            title: Text('Add comic source'),
            subtitle: Text(
              'Install a source by raw URL or from repository index',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: urlController,
              enabled: !controller.isBusy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Source URL',
                hintText: 'https://example.com/source.js',
              ),
              onSubmitted: (_) => _installFromUrl(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: controller.isBusy ? null : _installFromUrl,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _browseRepoIndex,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Comic Source List'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _reloadSources,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          ),
        ],
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

  Future<void> _browseRepoIndex() async {
    try {
      final response = await dio.get<String>(settings.sourceIndexUrl);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data == null) {
        throw StateError(
          'Failed to load source index: HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.data!);
      if (decoded is! List) {
        throw StateError('Source index is not a JSON list.');
      }

      if (!mounted) {
        return;
      }

      final selectedUrl = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final items = decoded.whereType<Map>().map((item) {
            return _RepoIndexItem.fromJson(Map<String, dynamic>.from(item));
          }).toList();
          return _RepoIndexSheet(
            indexUrl: settings.sourceIndexUrl,
            installedKeys: controller.sources
                .map((source) => source.key)
                .toSet(),
            items: items,
          );
        },
      );

      if (selectedUrl == null || !mounted) {
        return;
      }

      urlController.text = selectedUrl;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.source});

  final PluginSource source;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  PluginSource get source => widget.source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                source.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Chip(label: Text(source.version)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _capabilities(
              source,
            ).map((label) => Chip(label: Text(label))).toList(),
          ),
        ),
        children: [
          const Divider(height: 1),
          if (source.settings.isNotEmpty) ...[
            _SectionTitle(title: 'Settings'),
            ...source.settings.entries.map((entry) {
              return _SourceSettingTile(
                source: source,
                setting: entry.value,
                onChanged: () {
                  setState(() {});
                },
              );
            }),
          ],
          if (source.account != null) ...[
            _SectionTitle(title: 'Account'),
            _SourceAccountTile(source: source),
          ],
          ListTile(
            title: const Text('Path'),
            subtitle: Text(
              source.filePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: source.url.trim().isEmpty
                      ? null
                      : () => _updateSource(context, source),
                  icon: const Icon(Icons.update),
                  label: const Text('Update'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteSource(context, source),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ),
        ],
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

  Future<void> _updateSource(BuildContext context, PluginSource source) async {
    try {
      await PluginRuntimeController.instance.updateSource(source);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Updated ${source.name}')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteSource(BuildContext context, PluginSource source) async {
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
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SourceSettingTile extends StatelessWidget {
  const _SourceSettingTile({
    required this.source,
    required this.setting,
    required this.onChanged,
  });

  final PluginSource source;
  final PluginSourceSetting setting;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    source.data.putIfAbsent('settings', () => <String, dynamic>{});
    final currentValue =
        (source.data['settings'] as Map<String, dynamic>)[setting.key] ??
        setting.defaultValue;

    if (setting.type == 'switch') {
      return SwitchListTile(
        title: Text(setting.title),
        value: currentValue == true,
        onChanged: (value) async {
          (source.data['settings'] as Map<String, dynamic>)[setting.key] =
              value;
          await source.saveData();
          onChanged();
        },
      );
    }

    if (setting.type == 'select') {
      final selected = setting.options
          .where((option) => option.value == currentValue)
          .firstOrNull;
      return ListTile(
        title: Text(setting.title),
        subtitle: Text(selected?.text ?? currentValue?.toString() ?? ''),
        trailing: DropdownButton<String>(
          value: setting.options.any((option) => option.value == currentValue)
              ? currentValue.toString()
              : null,
          underline: const SizedBox.shrink(),
          items: [
            for (final option in setting.options)
              DropdownMenuItem<String>(
                value: option.value,
                child: Text(option.text),
              ),
          ],
          onChanged: (value) async {
            if (value == null) {
              return;
            }
            (source.data['settings'] as Map<String, dynamic>)[setting.key] =
                value;
            await source.saveData();
            onChanged();
          },
        ),
      );
    }

    return ListTile(
      title: Text(setting.title),
      subtitle: Text(currentValue?.toString() ?? ''),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _editInputSetting(context, currentValue?.toString() ?? ''),
    );
  }

  Future<void> _editInputSetting(
    BuildContext context,
    String initialValue,
  ) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(setting.title),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    final validator = setting.validator;
                    if (validator != null &&
                        validator.isNotEmpty &&
                        !RegExp(validator).hasMatch(value)) {
                      setState(() {
                        error = 'Invalid value';
                      });
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }
    (source.data['settings'] as Map<String, dynamic>)[setting.key] = result;
    await source.saveData();
    onChanged();
  }
}

class _SourceAccountTile extends StatefulWidget {
  const _SourceAccountTile({required this.source});

  final PluginSource source;

  @override
  State<_SourceAccountTile> createState() => _SourceAccountTileState();
}

class _SourceAccountTileState extends State<_SourceAccountTile> {
  bool isLoading = false;

  PluginSource get source => widget.source;

  @override
  Widget build(BuildContext context) {
    final account = source.account!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(source.isLogged ? 'Logged in' : 'Not logged in'),
            subtitle: Text(
              [
                if (account.login != null) 'Password login',
                if (account.cookieFields != null) 'Cookie login',
                if (account.loginWebsite != null) 'Web login URL available',
              ].join(' / '),
            ),
            trailing: isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!source.isLogged && account.login != null)
                FilledButton(
                  onPressed: isLoading ? null : _loginWithPassword,
                  child: const Text('Log in'),
                ),
              if (!source.isLogged && account.cookieFields != null)
                OutlinedButton(
                  onPressed: isLoading ? null : _loginWithCookies,
                  child: const Text('Cookies'),
                ),
              if (source.isLogged)
                OutlinedButton(
                  onPressed: isLoading ? null : _logout,
                  child: const Text('Log out'),
                ),
              if (source.isLogged &&
                  account.login != null &&
                  source.data['account'] is List)
                OutlinedButton(
                  onPressed: isLoading ? null : _relogin,
                  child: const Text('Re-login'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithPassword() async {
    final accountController = TextEditingController();
    final passwordController = TextEditingController();

    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Username',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Password',
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop((accountController.text.trim(), passwordController.text));
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (credentials == null) {
      return;
    }

    setState(() {
      isLoading = true;
    });
    try {
      final result = await source.account!.login!(
        credentials.$1,
        credentials.$2,
      );
      if (result.isError) {
        throw StateError(result.errorMessage!);
      }
      await source.saveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login successful')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithCookies() async {
    final fields = source.account!.cookieFields!;
    final controllers = {
      for (final field in fields) field: TextEditingController(),
    };

    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cookie Login'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields) ...[
                  TextField(
                    controller: controllers[field],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: field,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(fields.map((field) => controllers[field]!.text).toList());
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (values == null) {
      return;
    }

    setState(() {
      isLoading = true;
    });
    try {
      final result = await source.account!.validateCookies!(values);
      if (!result) {
        throw StateError('Invalid cookies');
      }
      source.data['account'] = 'ok';
      await source.saveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cookie login successful')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _relogin() async {
    final accountData = source.data['account'];
    if (accountData is! List || accountData.length < 2) {
      return;
    }

    setState(() {
      isLoading = true;
    });
    try {
      final result = await source.account!.login!(
        accountData[0].toString(),
        accountData[1].toString(),
      );
      if (result.isError) {
        throw StateError(result.errorMessage!);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Re-login successful')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    source.data['account'] = null;
    source.account?.logout();
    await source.saveData();
    if (!mounted) {
      return;
    }
    setState(() {});
  }
}

class _RepoIndexSheet extends StatelessWidget {
  const _RepoIndexSheet({
    required this.indexUrl,
    required this.installedKeys,
    required this.items,
  });

  final String indexUrl;
  final Set<String> installedKeys;
  final List<_RepoIndexItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Comic Source List'),
            subtitle: Text(indexUrl),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final installed = installedKeys.contains(item.key);
                return ListTile(
                  title: Text(item.name),
                  subtitle: Text('${item.key} - v${item.version}'),
                  trailing: installed ? const Icon(Icons.check) : null,
                  onTap: installed
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(item.resolvedUrl(indexUrl)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoIndexItem {
  const _RepoIndexItem({
    required this.name,
    required this.key,
    required this.version,
    this.url,
    this.fileName,
  });

  final String name;
  final String key;
  final String version;
  final String? url;
  final String? fileName;

  factory _RepoIndexItem.fromJson(Map<String, dynamic> json) {
    return _RepoIndexItem(
      name: json['name']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      url: json['url']?.toString(),
      fileName: json['fileName']?.toString() ?? json['filename']?.toString(),
    );
  }

  String resolvedUrl(String indexUrl) {
    if (url != null && url!.isNotEmpty) {
      return url!;
    }
    if (fileName == null || fileName!.isEmpty) {
      throw StateError('Source entry does not contain url or fileName.');
    }

    final uri = Uri.parse(indexUrl);
    final segments = [...uri.pathSegments];
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    return uri.replace(pathSegments: [...segments, fileName!]).toString();
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
