import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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

  String? downloadPath;
  String? cachePath;
  int cacheSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onSettingsChanged);
    DownloadController.instance.addListener(_onSettingsChanged);
    PluginRuntimeController.instance.addListener(_onSettingsChanged);
    HistoryController.instance.addListener(_onSettingsChanged);
    unawaited(_refreshStorageInfo());
  }

  @override
  void dispose() {
    controller.removeListener(_onSettingsChanged);
    DownloadController.instance.removeListener(_onSettingsChanged);
    PluginRuntimeController.instance.removeListener(_onSettingsChanged);
    HistoryController.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SettingsHero(
            title: l10n.isChinese ? '设置' : 'Settings',
            subtitle: l10n.isChinese
                ? '浏览设置项'
                : 'Begin to Settings',
          ),
          const SizedBox(height: 20),
          _SettingsMenuCard(
            title: l10n.settingsReader,
            subtitle: l10n.settingsPrefetchPagesSubtitle(
              controller.readerPrefetchCount,
            ),
            icon: Icons.chrome_reader_mode_outlined,
            onTap: () => _openSection(context, const _ReaderSettingsPage()),
          ),
          const SizedBox(height: 14),
          _SettingsMenuCard(
            title: l10n.settingsAppearance,
            subtitle:
                '${l10n.languageLabel(controller.language)} 路 ${l10n.themePresetLabel(controller.themePreset)}',
            icon: Icons.palette_outlined,
            onTap: () => _openSection(context, const _AppearanceSettingsPage()),
          ),
          const SizedBox(height: 14),
          _SettingsMenuCard(
            title: l10n.settingsNetwork,
            subtitle: controller.sourceIndexUrl,
            icon: Icons.public_outlined,
            onTap: () => _openSection(context, const _NetworkSettingsPage()),
          ),
          const SizedBox(height: 14),
          _SettingsMenuCard(
            title: l10n.settingsDownloads,
            subtitle: downloadPath ??
                l10n.settingsDownloadedComicsCount(
                  DownloadController.instance.downloads.length,
                ),
            icon: Icons.download_outlined,
            onTap: () => _openSection(context, const _DownloadsSettingsPage()),
          ),
          const SizedBox(height: 14),
          _SettingsMenuCard(
            title: l10n.settingsApp,
            subtitle:
                '${_formatBytes(cacheSizeBytes)} 路 ${l10n.settingsInstalledSourcesCount(PluginRuntimeController.instance.sources.length)}',
            icon: Icons.apps_outlined,
            onTap: () => _openSection(context, const _AppSettingsPage()),
          ),
          const SizedBox(height: 14),
          _SettingsMenuCard(
            title: l10n.settingsAbout,
            subtitle: l10n.settingsGithubSubtitle,
            icon: Icons.info_outline,
            onTap: () => _openSection(context, const _AboutSettingsPage()),
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

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(_refreshStorageInfo());
  }

  void _openSection(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }
}

class _ReaderSettingsPage extends StatefulWidget {
  const _ReaderSettingsPage();

  @override
  State<_ReaderSettingsPage> createState() => _ReaderSettingsPageState();
}

class _ReaderSettingsPageState extends State<_ReaderSettingsPage> {
  final controller = SettingsController.instance;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsReader,
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
        ],
      ),
    );
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _AppearanceSettingsPage extends StatefulWidget {
  const _AppearanceSettingsPage();

  @override
  State<_AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<_AppearanceSettingsPage> {
  final controller = SettingsController.instance;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsAppearance,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
        ],
      ),
    );
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _NetworkSettingsPage extends StatefulWidget {
  const _NetworkSettingsPage();

  @override
  State<_NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<_NetworkSettingsPage> {
  final controller = SettingsController.instance;
  late final TextEditingController sourceIndexController =
      TextEditingController(text: controller.sourceIndexUrl);

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    sourceIndexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsNetwork,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
                      onSubmitted: controller.setSourceIndexUrl,
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
        ],
      ),
    );
  }

  void _handleChange() {
    if (!mounted) {
      return;
    }
    if (sourceIndexController.text != controller.sourceIndexUrl) {
      sourceIndexController.text = controller.sourceIndexUrl;
    }
    setState(() {});
  }
}

class _DownloadsSettingsPage extends StatefulWidget {
  const _DownloadsSettingsPage();

  @override
  State<_DownloadsSettingsPage> createState() => _DownloadsSettingsPageState();
}

class _DownloadsSettingsPageState extends State<_DownloadsSettingsPage> {
  final controller = SettingsController.instance;

  String? downloadPath;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
    DownloadController.instance.addListener(_handleChange);
    DownloadController.instance.initialize();
    unawaited(_refreshStorageInfo());
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    DownloadController.instance.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsDownloads,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
                    : () => _openDirectory(context, downloadPath!),
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
        ],
      ),
    );
  }

  Future<void> _refreshStorageInfo() async {
    final nextDownloadPath = await DownloadController.instance.getStoragePath();
    if (!mounted) {
      return;
    }
    setState(() {
      downloadPath = nextDownloadPath;
    });
  }

  Future<void> _pickDownloadDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      await _runBusyDialog(navigator, () async {
        await DownloadController.instance.relocateLibrary(selected);
        await _refreshStorageInfo();
      });
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsSelectFolderFailed);
    }
  }

  Future<void> _resetDownloadDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      await _runBusyDialog(navigator, () async {
        await DownloadController.instance.relocateLibrary(null);
        await _refreshStorageInfo();
      });
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdateFailed);
    }
  }

  void _handleChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(_refreshStorageInfo());
  }
}

class _AppSettingsPage extends StatefulWidget {
  const _AppSettingsPage();

  @override
  State<_AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<_AppSettingsPage> {
  final controller = SettingsController.instance;

  String? cachePath;
  int cacheSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
    PluginRuntimeController.instance.addListener(_handleChange);
    HistoryController.instance.addListener(_handleChange);
    unawaited(_refreshStorageInfo());
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    PluginRuntimeController.instance.removeListener(_handleChange);
    HistoryController.instance.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsApp,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
                    : () => _openDirectory(context, cachePath!),
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
        ],
      ),
    );
  }

  Future<void> _refreshStorageInfo() async {
    final nextCachePath = await ReaderImageCache.instance.currentRootPath();
    final nextCacheSize = await ReaderImageCache.instance.diskUsageBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      cachePath = nextCachePath;
      cacheSizeBytes = nextCacheSize;
    });
  }

  Future<void> _pickCacheDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      await _runBusyDialog(navigator, () async {
        await controller.setReaderCacheDirectoryPath(selected);
        await ReaderImageCache.instance.reloadConfiguration();
        await _refreshStorageInfo();
      });
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsSelectFolderFailed);
    }
  }

  Future<void> _resetCacheDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      await _runBusyDialog(navigator, () async {
        await controller.setReaderCacheDirectoryPath(null);
        await ReaderImageCache.instance.reloadConfiguration();
        await _refreshStorageInfo();
      });
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSettingsMessage(context, l10n.settingsPathUpdateFailed);
    }
  }

  Future<void> _clearReaderCache() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    await _runBusyDialog(navigator, () async {
      await ReaderImageCache.instance.clearDiskCache();
      await _refreshStorageInfo();
    });
    if (!mounted) {
      return;
    }
    _showSettingsMessage(context, l10n.settingsCacheCleared);
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

  void _handleChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(_refreshStorageInfo());
  }
}

class _AboutSettingsPage extends StatefulWidget {
  const _AboutSettingsPage();

  @override
  State<_AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<_AboutSettingsPage> {
  static final _githubUri = Uri.parse('https://github.com/WEP-56/EZVenera');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SettingsSectionScaffold(
      title: l10n.settingsAbout,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
              ListTile(
                title: Text(l10n.settingsCheckUpdate),
                subtitle: Text(
                  l10n.settingsLatestVersionLabel('GitHub Release'),
                ),
                trailing: const Icon(Icons.system_update_alt_outlined),
                onTap: _checkForUpdates,
              ),
            ],
          ),
        ],
      ),
    );
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
    _showSettingsMessage(context, l10n.settingsLinkOpenFailed);
  }

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final release = await _fetchLatestRelease();
      if (!_isNewerVersion(release.version, currentVersion)) {
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(l10n.settingsCheckUpdate),
              content: Text(l10n.settingsNoUpdate),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            );
          },
        );
        return;
      }

      if (!mounted) {
        return;
      }
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l10n.settingsUpdateDialogTitle),
            content: Text(
              '${l10n.settingsLatestVersionLabel(release.tag)}\nCurrent: $currentVersion',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.settingsLater),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.settingsUpdateNow),
              ),
            ],
          );
        },
      );

      if (shouldDownload != true) {
        return;
      }

      final downloadedFile = await _downloadLatestRelease(release);
      if (!mounted) {
        return;
      }
      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text(l10n.settingsCheckUpdate),
            content: Text(l10n.settingsDownloadComplete),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.settingsInstallNow),
              ),
            ],
          );
        },
      );

      if (shouldInstall == true) {
        await _launchInstaller(downloadedFile.path);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSettingsMessage(
        context,
        '${l10n.settingsUpdateFailed} ${error.toString()}',
      );
    }
  }

  Future<_ReleaseAsset> _fetchLatestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/WEP-56/EZvenera/releases/latest',
    );
    final response = await Dio().getUri<Map<String, dynamic>>(uri);
    final data = response.data;
    if (response.statusCode != 200 || data == null) {
      throw StateError('Invalid update response.');
    }
    final tag = data['tag_name']?.toString() ?? '';
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    final assets = (data['assets'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final asset = _pickReleaseAsset(version, tag, assets);
    return asset;
  }

  _ReleaseAsset _pickReleaseAsset(
    String version,
    String tag,
    List<Map<String, dynamic>> assets,
  ) {
    final targetName = Platform.isWindows
        ? 'windows-setup.exe'
        : Platform.isAndroid
        ? 'android-release.apk'
        : '';
    if (targetName.isEmpty) {
      throw UnsupportedError('Update is not supported on this platform.');
    }

    for (final asset in assets) {
      final name = asset['name']?.toString() ?? '';
      if (name.endsWith(targetName)) {
        return _ReleaseAsset(
          tag: tag,
          version: version,
          name: name,
          url: asset['browser_download_url']?.toString() ?? '',
        );
      }
    }
    throw StateError('No matching installer asset found.');
  }

  bool _isNewerVersion(String latest, String current) {
    List<int> parse(String input) {
      return input
          .split('.')
          .map(
            (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          )
          .toList();
    }

    final latestParts = parse(latest);
    final currentParts = parse(current);
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var index = 0; index < length; index++) {
      final left = index < latestParts.length ? latestParts[index] : 0;
      final right = index < currentParts.length ? currentParts[index] : 0;
      if (left > right) {
        return true;
      }
      if (left < right) {
        return false;
      }
    }
    return false;
  }

  Future<File> _downloadLatestRelease(_ReleaseAsset release) async {
    final l10n = AppLocalizations.of(context);
    final supportDirectory = await getApplicationSupportDirectory();
    final updateRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}updates',
    );
    await updateRoot.create(recursive: true);
    final file = File(
      '${updateRoot.path}${Platform.pathSeparator}${release.name}',
    );

    if (!mounted) {
      return file;
    }

    final progressNotifier = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsCheckUpdate),
          content: ValueListenableBuilder<double?>(
            valueListenable: progressNotifier,
            builder: (context, progress, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsDownloadingUpdate),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(
                    progress == null
                        ? '0%'
                        : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      await Dio().download(
        release.url,
        file.path,
        onReceiveProgress: (received, total) {
          if (total <= 0) {
            return;
          }
          progressNotifier.value = received / total;
        },
      );
    } finally {
      progressNotifier.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    return file;
  }

  Future<void> _launchInstaller(String path) async {
    if (Platform.isWindows) {
      await Process.start(path, const <String>[], mode: ProcessStartMode.detached);
      exit(0);
    }

    if (Platform.isAndroid) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        throw StateError(
          result.message.isEmpty
              ? 'Unable to launch installer.'
              : result.message,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      SystemNavigator.pop();
      return;
    }

    final launched = await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Unable to launch installer.');
    }
  }
}

class _SettingsSectionScaffold extends StatelessWidget {
  const _SettingsSectionScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMenuCard extends StatelessWidget {
  const _SettingsMenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
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

class _ReleaseAsset {
  const _ReleaseAsset({
    required this.tag,
    required this.version,
    required this.name,
    required this.url,
  });

  final String tag;
  final String version;
  final String name;
  final String url;
}

Future<void> _runBusyDialog(
  NavigatorState navigator,
  Future<void> Function() action,
) async {
  showDialog<void>(
    context: navigator.context,
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
    if (navigator.mounted) {
      navigator.pop();
    }
  }
}

void _showSettingsMessage(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _openDirectory(BuildContext context, String path) async {
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
    if (!context.mounted) {
      return;
    }
    _showSettingsMessage(context, l10n.settingsDirectoryOpenFailed);
  }
}

String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => l10n.light,
    ThemeMode.dark => l10n.dark,
    ThemeMode.system => l10n.systemLabel,
  };
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
