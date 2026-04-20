import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../downloads/download_controller.dart';
import '../library/history_controller.dart';
import '../localization/app_localizations.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../reader/reader_image_cache.dart';
import '../settings/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final controller = SettingsController.instance;
  late final TextEditingController sourceIndexController =
      TextEditingController(text: controller.sourceIndexUrl);

  static final _githubUri = Uri.parse('https://github.com/WEP-56/EZVenera');

  String? downloadPath;
  String? cachePath;
  int cacheSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onSettingsChanged);
    _refreshStorageInfo();
  }

  @override
  void dispose() {
    controller.removeListener(_onSettingsChanged);
    sourceIndexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SettingsGroup(
            title: l10n.settingsReader,
            icon: Icons.chrome_reader_mode_outlined,
            children: [
              SwitchListTile(
                title: Text(l10n.settingsReaderShowTapGuide),
                subtitle: Text(l10n.settingsReaderShowTapGuideSubtitle),
                value: controller.readerShowTapGuide,
                onChanged: controller.setReaderShowTapGuide,
              ),
              ListTile(
                title: Text(l10n.settingsPrefetchPages),
                subtitle: Text(
                  l10n.settingsPrefetchPagesSubtitle(
                    controller.readerPrefetchCount,
                  ),
                ),
                trailing: DropdownButton<int>(
                  value: controller.readerPrefetchCount,
                  underline: const SizedBox.shrink(),
                  items: const [1, 2, 3, 4, 5, 6]
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.setReaderPrefetchCount(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: l10n.settingsAppearance,
            icon: Icons.palette_outlined,
            children: [
              ListTile(
                title: Text(l10n.settingsLanguage),
                subtitle: Text(l10n.settingsLanguageSubtitle),
                trailing: DropdownButton<AppLanguageOption>(
                  value: controller.language,
                  underline: const SizedBox.shrink(),
                  items: AppLanguageOption.values
                      .map(
                        (value) => DropdownMenuItem<AppLanguageOption>(
                          value: value,
                          child: Text(l10n.languageLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.setLanguage(value);
                    }
                  },
                ),
              ),
              ListTile(
                title: Text(l10n.settingsThemeMode),
                subtitle: Text(_themeModeLabel(l10n, controller.themeMode)),
                trailing: DropdownButton<ThemeMode>(
                  value: controller.themeMode,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(l10n.systemLabel),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(l10n.light),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(l10n.dark),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.setThemeMode(value);
                    }
                  },
                ),
              ),
              ListTile(
                title: Text(l10n.settingsThemeColor),
                subtitle: Text(l10n.themePresetLabel(controller.themePreset)),
                trailing: DropdownButton<AppThemePreset>(
                  value: controller.themePreset,
                  underline: const SizedBox.shrink(),
                  items: AppThemePreset.values
                      .map(
                        (value) => DropdownMenuItem<AppThemePreset>(
                          value: value,
                          child: Text(l10n.themePresetLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.setThemePreset(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: l10n.settingsNetwork,
            icon: Icons.public_outlined,
            children: [
              ListTile(
                title: Text(l10n.settingsSourceIndexUrl),
                subtitle: Text(
                  controller.sourceIndexUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: sourceIndexController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.settingsIndexUrl,
                        hintText: SettingsController.defaultSourceIndexUrl,
                      ),
                      onSubmitted: (value) =>
                          controller.setSourceIndexUrl(value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () {
                            controller.setSourceIndexUrl(
                              sourceIndexController.text,
                            );
                          },
                          child: Text(l10n.save),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {
                            sourceIndexController.text =
                                SettingsController.defaultSourceIndexUrl;
                            controller.setSourceIndexUrl(
                              SettingsController.defaultSourceIndexUrl,
                            );
                          },
                          child: Text(l10n.reset),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: l10n.settingsDownloads,
            icon: Icons.download_outlined,
            children: [
              SwitchListTile(
                title: Text(l10n.settingsSaveDownloadedCover),
                subtitle: Text(l10n.settingsSaveDownloadedCoverSubtitle),
                value: controller.downloadSaveCover,
                onChanged: controller.setDownloadSaveCover,
              ),
              _PathSettingTile(
                title: l10n.settingsDownloadDirectory,
                subtitle: l10n.settingsDownloadDirectorySubtitle,
                path: downloadPath,
                openLabel: l10n.settingsOpenFolder,
                selectLabel: l10n.settingsSelectFolder,
                defaultLabel: l10n.settingsUseDefaultPath,
                onOpen: downloadPath == null
                    ? null
                    : () => _openDirectory(downloadPath!),
                onSelect: _pickDownloadDirectory,
                onUseDefault: controller.downloadDirectoryPath == null
                    ? null
                    : _resetDownloadDirectory,
              ),
              ListTile(
                title: Text(l10n.localDownloadedComics),
                subtitle: Text(
                  l10n.settingsDownloadedComicsCount(
                    DownloadController.instance.downloads.length,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: l10n.settingsApp,
            icon: Icons.apps_outlined,
            children: [
              _PathSettingTile(
                title: l10n.settingsReaderCacheDirectory,
                subtitle: l10n.settingsReaderCacheDirectorySubtitle,
                path: cachePath,
                openLabel: l10n.settingsOpenFolder,
                selectLabel: l10n.settingsSelectFolder,
                defaultLabel: l10n.settingsUseDefaultPath,
                onOpen: cachePath == null
                    ? null
                    : () => _openDirectory(cachePath!),
                onSelect: _pickCacheDirectory,
                onUseDefault: controller.readerCacheDirectoryPath == null
                    ? null
                    : _resetCacheDirectory,
              ),
              ListTile(
                title: Text(l10n.settingsCacheSize),
                subtitle: Text(_formatBytes(cacheSizeBytes)),
              ),
              ListTile(
                title: Text(l10n.settingsCacheLimit),
                subtitle: Text(
                  l10n.settingsCacheLimitSubtitle(
                    controller.readerCacheLimitMb,
                  ),
                ),
                trailing: DropdownButton<int>(
                  value: controller.readerCacheLimitMb,
                  underline: const SizedBox.shrink(),
                  items: const [128, 256, 512, 1024, 2048, 4096]
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value MB'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) {
                      return;
                    }
                    await controller.setReaderCacheLimitMb(value);
                    await ReaderImageCache.instance.reloadConfiguration();
                    await _refreshStorageInfo();
                  },
                ),
              ),
              ListTile(
                title: Text(l10n.settingsClearCache),
                subtitle: Text(l10n.settingsClearCacheSubtitle),
                trailing: const Icon(Icons.cleaning_services_outlined),
                onTap: _clearReaderCache,
              ),
              ListTile(
                title: Text(l10n.settingsInstalledSources),
                subtitle: Text(
                  l10n.settingsInstalledSourcesCount(
                    PluginRuntimeController.instance.sources.length,
                  ),
                ),
              ),
              ListTile(
                title: Text(l10n.settingsReadingHistory),
                subtitle: Text(
                  l10n.settingsReadingHistoryCount(
                    HistoryController.instance.entries.length,
                  ),
                ),
              ),
              ListTile(
                title: Text(l10n.settingsResetSettings),
                subtitle: Text(l10n.settingsResetSettingsSubtitle),
                trailing: const Icon(Icons.restore),
                onTap: _confirmReset,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: l10n.settingsAbout,
            icon: Icons.info_outline,
            children: [
              ListTile(
                title: const Text('EZVenera'),
                subtitle: Text(l10n.settingsAboutDescription),
              ),
              ListTile(
                title: Text(l10n.settingsSourceRepository),
                subtitle: Text(l10n.settingsSourceRepositorySubtitle),
              ),
              ListTile(
                title: Text(l10n.settingsGithub),
                subtitle: Text(l10n.settingsGithubSubtitle),
                trailing: const Icon(Icons.open_in_new),
                onTap: _openGithub,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshStorageInfo() async {
    final nextDownloadPath = await DownloadController.instance.getStoragePath();
    final nextCachePath = await ReaderImageCache.instance.currentRootPath();
    final nextCacheSize = await ReaderImageCache.instance.diskUsageBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      downloadPath = nextDownloadPath;
      cachePath = nextCachePath;
      cacheSizeBytes = nextCacheSize;
    });
  }

  Future<void> _pickDownloadDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) {
        return;
      }
      await _runBusy(() async {
        await DownloadController.instance.relocateLibrary(selected);
        await _refreshStorageInfo();
      });
      _showMessage(l10n.settingsPathUpdated);
    } catch (_) {
      _showMessage(l10n.settingsSelectFolderFailed);
    }
  }

  Future<void> _resetDownloadDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      await _runBusy(() async {
        await DownloadController.instance.relocateLibrary(null);
        await _refreshStorageInfo();
      });
      _showMessage(l10n.settingsPathUpdated);
    } catch (_) {
      _showMessage(l10n.settingsPathUpdateFailed);
    }
  }

  Future<void> _pickCacheDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) {
        return;
      }
      await _runBusy(() async {
        await controller.setReaderCacheDirectoryPath(selected);
        await ReaderImageCache.instance.reloadConfiguration();
        await _refreshStorageInfo();
      });
      _showMessage(l10n.settingsPathUpdated);
    } catch (_) {
      _showMessage(l10n.settingsSelectFolderFailed);
    }
  }

  Future<void> _resetCacheDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      await _runBusy(() async {
        await controller.setReaderCacheDirectoryPath(null);
        await ReaderImageCache.instance.reloadConfiguration();
        await _refreshStorageInfo();
      });
      _showMessage(l10n.settingsPathUpdated);
    } catch (_) {
      _showMessage(l10n.settingsPathUpdateFailed);
    }
  }

  Future<void> _clearReaderCache() async {
    final l10n = AppLocalizations.of(context);
    await _runBusy(() async {
      await ReaderImageCache.instance.clearDiskCache();
      await _refreshStorageInfo();
    });
    _showMessage(l10n.settingsCacheCleared);
  }

  Future<void> _openDirectory(String path) async {
    final l10n = AppLocalizations.of(context);
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
        return;
      }
      final opened = await launchUrl(
        Uri.directory(path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('open failed');
      }
    } catch (_) {
      _showMessage(l10n.settingsDirectoryOpenFailed);
    }
  }

  Future<void> _confirmReset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsResetDialogTitle),
          content: Text(l10n.settingsResetDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.reset),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await controller.reset();
    await ReaderImageCache.instance.reloadConfiguration();
    await DownloadController.instance.relocateLibrary(null);
    await _refreshStorageInfo();
  }

  Future<void> _openGithub() async {
    final l10n = AppLocalizations.of(context);
    final success = await launchUrl(
      _githubUri,
      mode: LaunchMode.externalApplication,
    );
    if (success || !mounted) {
      return;
    }
    _showMessage(l10n.settingsLinkOpenFailed);
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const PopScope(
          canPop: false,
          child: Center(
            child: SizedBox.square(
              dimension: 36,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ),
        );
      },
    );

    try {
      await action();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => l10n.light,
      ThemeMode.dark => l10n.dark,
      ThemeMode.system => l10n.systemLabel,
    };
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    if (sourceIndexController.text != controller.sourceIndexUrl) {
      sourceIndexController.text = controller.sourceIndexUrl;
    }
    setState(() {});
    _refreshStorageInfo();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _PathSettingTile extends StatelessWidget {
  const _PathSettingTile({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.openLabel,
    required this.selectLabel,
    required this.defaultLabel,
    required this.onSelect,
    required this.onOpen,
    required this.onUseDefault,
  });

  final String title;
  final String subtitle;
  final String? path;
  final String openLabel;
  final String selectLabel;
  final String defaultLabel;
  final VoidCallback onSelect;
  final VoidCallback? onOpen;
  final VoidCallback? onUseDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                path ?? '-',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: onSelect, child: Text(selectLabel)),
                  OutlinedButton(onPressed: onOpen, child: Text(openLabel)),
                  OutlinedButton(
                    onPressed: onUseDefault,
                    child: Text(defaultLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
