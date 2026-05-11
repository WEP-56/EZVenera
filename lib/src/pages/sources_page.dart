import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../settings/settings_controller.dart';
import 'plugin_webview_login_page.dart';

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
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(l10n.sourcesAddTitle),
            subtitle: Text(l10n.sourcesAddSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: urlController,
              enabled: !controller.isBusy,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.sourcesUrlLabel,
                hintText: l10n.sourcesUrlHint,
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
                  label: Text(l10n.sourcesInstall),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _browseRepoIndex,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: Text(l10n.sourcesComicSourceList),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _installFromLocalFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l10n.sourcesInstallLocal),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _reloadSources,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.sourcesReload),
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
    final l10n = AppLocalizations.of(context);

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
          Text(l10n.sourcesNoSources, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            l10n.sourcesNoSourcesBody,
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

    final l10n = AppLocalizations.of(context);
    try {
      final source = await controller.installFromUrl(url);
      if (!mounted) {
        return;
      }
      urlController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesInstalled(source.name))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesInstallFailed)),
      );
    }
  }

  Future<void> _reloadSources() async {
    final l10n = AppLocalizations.of(context);
    try {
      await controller.reload();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sourcesReloaded)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sourcesReloadFailed)));
    }
  }

  Future<void> _installFromLocalFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      const typeGroup = XTypeGroup(
        label: 'JavaScript',
        extensions: <String>['js'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (file == null) {
        return;
      }

      final source = await controller.installFromLocalFile(file.path);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesInstalled(source.name))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                            const SizedBox(width: 8),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _capabilities(
                            source,
                          ).map((label) => Chip(label: Text(label))).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              heightFactor: isExpanded ? 1 : 0,
              child: Column(
                children: [
                  const Divider(height: 1),
                  if (source.settings.isNotEmpty) ...[
                    _SectionTitle(title: l10n.sourcesSettings),
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
                    _SectionTitle(title: l10n.sourcesAccount),
                    _SourceAccountTile(source: source),
                  ],
                  ListTile(
                    title: Text(l10n.sourcesPath),
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
                          onPressed: source.updateUrl.isEmpty
                              ? null
                              : () => _updateSource(context, source),
                          icon: const Icon(Icons.update),
                          label: Text(l10n.sourcesUpdate),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _deleteSource(context, source),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.sourcesDelete),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final l10n = AppLocalizations.of(context);
    try {
      await PluginRuntimeController.instance.updateSource(source);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesUpdated(source.name))),
      );
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.sourcesDeleteTitle),
          content: Text(l10n.sourcesDeleteBody(source.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.sourcesDelete),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesDeleted(source.name))),
      );
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
    final l10n = AppLocalizations.of(context);
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
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    final validator = setting.validator;
                    if (validator != null &&
                        validator.isNotEmpty &&
                        !RegExp(validator).hasMatch(value)) {
                      setState(() {
                        error = l10n.sourcesInvalidValue;
                      });
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  child: Text(l10n.save),
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
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              source.isLogged ? l10n.sourcesLoggedIn : l10n.sourcesNotLoggedIn,
            ),
            subtitle: Text(
              [
                if (account.login != null) l10n.sourcesPasswordLogin,
                if (account.cookieFields != null) l10n.sourcesCookieLogin,
                if (account.loginWebsite != null)
                  l10n.sourcesWebLoginAvailable,
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
                  child: Text(l10n.sourcesLogIn),
                ),
              if (!source.isLogged && account.cookieFields != null)
                OutlinedButton(
                  onPressed: isLoading ? null : _loginWithCookies,
                  child: Text(l10n.sourcesCookies),
                ),
              if (!source.isLogged && account.loginWebsite != null)
                OutlinedButton(
                  onPressed: isLoading ? null : _loginWithWebview,
                  child: Text(l10n.sourcesWebview),
                ),
              if (source.isLogged)
                OutlinedButton(
                  onPressed: isLoading ? null : _logout,
                  child: Text(l10n.sourcesLogOut),
                ),
              if (source.isLogged &&
                  account.login != null &&
                  source.data['account'] is List)
                OutlinedButton(
                  onPressed: isLoading ? null : _relogin,
                  child: Text(l10n.sourcesReLogin),
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
    final l10n = AppLocalizations.of(context);

    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.sourcesLogIn),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.sourcesUsername,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.sourcesPassword,
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop((accountController.text.trim(), passwordController.text));
              },
              child: Text(l10n.sourcesContinue),
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
      source.markLoggedIn(accountData: source.data['account']);
      await source.saveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sourcesLoginSuccess)));
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
    final l10n = AppLocalizations.of(context);

    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.sourcesCookieLoginTitle),
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
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(fields.map((field) => controllers[field]!.text).toList());
              },
              child: Text(l10n.sourcesContinue),
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
        throw StateError(l10n.sourcesInvalidCookies);
      }
      source.markLoggedIn();
      await source.saveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sourcesCookieLoginSuccess)));
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
    final l10n = AppLocalizations.of(context);

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
      source.markLoggedIn(accountData: source.data['account']);
      await source.saveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.sourcesReloginSuccess)));
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
    source.markLoggedOut();
    source.account?.logout();
    await source.saveData();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _loginWithWebview() async {
    if (source.account?.loginWebsite == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (source.account?.checkLoginStatus == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourcesWebviewNoStatus)),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PluginWebviewLoginPage(source: source),
      ),
    );

    if (!mounted || result != true) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.sourcesWebviewLoginSuccess)));
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
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(l10n.sourcesComicSourceList),
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
