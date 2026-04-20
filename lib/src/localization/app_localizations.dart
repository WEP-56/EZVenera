import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

enum AppLanguageOption { system, english, simplifiedChinese }

enum AppThemePreset { teal, amber, rose, blue, forest }

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh', 'CN')];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return value ?? AppLocalizations(const Locale('en'));
  }

  bool get isChinese => locale.languageCode == 'zh';

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'nav.search': 'Search',
      'nav.category': 'Category',
      'nav.local': 'Local',
      'nav.sources': 'Sources',
      'nav.settings': 'Settings',
      'local.history': 'History',
      'local.favorites': 'Favorites',
      'local.downloads': 'Downloads',
      'local.activeTasks': 'Active Tasks',
      'local.downloadedComics': 'Downloaded Comics',
      'local.noDownloads': 'No downloads yet',
      'local.noDownloadsBody':
          'Use the detail page Download button to save comics locally.',
      'local.noHistory': 'No history yet',
      'local.noHistoryBody':
          'Open a chapter in the reader and it will appear here.',
      'local.noFavorites': 'No favorites yet',
      'local.noFavoritesBody':
          'Use the detail page Favorite button to add comics here.',
      'local.favoriteMeta': 'Favorite',
      'common.open': 'Open',
      'common.delete': 'Delete',
      'common.save': 'Save',
      'common.reset': 'Reset',
      'common.cancel': 'Cancel',
      'common.system': 'System',
      'common.light': 'Light',
      'common.dark': 'Dark',
      'settings.reader': 'Reader',
      'settings.appearance': 'Appearance',
      'settings.network': 'Network',
      'settings.downloads': 'Downloads',
      'settings.app': 'App',
      'settings.about': 'About / Debug',
      'settings.language': 'Language',
      'settings.languageSubtitle': 'Choose the app display language.',
      'settings.themeMode': 'Theme Mode',
      'settings.themeColor': 'Theme Color',
      'settings.readerShowTapGuide': 'Show tap guide',
      'settings.readerShowTapGuideSubtitle':
          'Display the right-bottom hint for page turning and controls.',
      'settings.prefetchPages': 'Prefetch pages',
      'settings.prefetchPagesSubtitle':
          'Preload {count} page(s) ahead in the reader.',
      'settings.sourceIndexUrl': 'Source Index URL',
      'settings.indexUrl': 'Index URL',
      'settings.saveDownloadedCover': 'Save downloaded cover',
      'settings.saveDownloadedCoverSubtitle':
          'Store the cover image in the local download library for cards and history.',
      'settings.downloadDirectory': 'Download Directory',
      'settings.downloadDirectorySubtitle':
          'Choose where downloaded comics and the local download library are stored.',
      'settings.readerCacheDirectory': 'Reader Cache Directory',
      'settings.readerCacheDirectorySubtitle':
          'Choose where reader image cache files are stored.',
      'settings.openFolder': 'Open Folder',
      'settings.selectFolder': 'Select Folder',
      'settings.useDefaultPath': 'Use Default',
      'settings.cacheSize': 'Cache Size',
      'settings.cacheLimit': 'Cache Limit',
      'settings.cacheLimitSubtitle': 'Keep up to {count} MB of reader cache.',
      'settings.clearCache': 'Clear Cache',
      'settings.clearCacheSubtitle':
          'Delete all cached reader images in the current cache directory.',
      'settings.cacheCleared': 'Reader cache cleared.',
      'settings.pathUpdated': 'Path updated successfully.',
      'settings.pathUpdateFailed': 'Failed to update the path.',
      'settings.directoryOpenFailed': 'Failed to open the folder.',
      'settings.selectFolderFailed': 'Failed to open folder selector.',
      'settings.downloadedComicsCount': '{count} saved comic(s)',
      'settings.installedSources': 'Installed Sources',
      'settings.installedSourcesCount': '{count} source(s) loaded',
      'settings.readingHistory': 'Reading History',
      'settings.readingHistoryCount': '{count} item(s) stored',
      'settings.resetSettings': 'Reset Settings',
      'settings.resetSettingsSubtitle':
          'Reset EZVenera settings to the current default profile.',
      'settings.resetDialogTitle': 'Reset Settings',
      'settings.resetDialogBody':
          'Reset current EZVenera settings to defaults?',
      'settings.aboutDescription':
          'A simplified, maintainable fork direction of Venera focused on Windows, Android, plugin compatibility, and long-term clarity.',
      'settings.sourceRepository': 'Source Repository',
      'settings.sourceRepositorySubtitle':
          'EZVenera-config is the default plugin index for this app.',
      'settings.github': 'GitHub',
      'settings.githubSubtitle':
          'Open the EZVenera repository in your browser.',
      'settings.linkOpenFailed':
          'Failed to open the link in the system browser.',
      'language.system': 'System',
      'language.english': 'English',
      'language.simplifiedChinese': '简体中文',
      'themeColor.teal': 'Teal',
      'themeColor.amber': 'Amber',
      'themeColor.rose': 'Rose',
      'themeColor.blue': 'Blue',
      'themeColor.forest': 'Forest',
    },
    'zh': {
      'nav.search': '搜索',
      'nav.category': '分类',
      'nav.local': '本地',
      'nav.sources': '图源',
      'nav.settings': '设置',
      'local.history': '历史',
      'local.favorites': '收藏',
      'local.downloads': '下载',
      'local.activeTasks': '进行中的任务',
      'local.downloadedComics': '已下载漫画',
      'local.noDownloads': '还没有下载内容',
      'local.noDownloadsBody': '在详情页点击下载按钮后，漫画会保存在本地。',
      'local.noHistory': '还没有历史记录',
      'local.noHistoryBody': '打开章节开始阅读后，这里就会出现记录。',
      'local.noFavorites': '还没有收藏',
      'local.noFavoritesBody': '在详情页点击收藏按钮后，这里会显示收藏内容。',
      'local.favoriteMeta': '收藏',
      'common.open': '打开',
      'common.delete': '删除',
      'common.save': '保存',
      'common.reset': '重置',
      'common.cancel': '取消',
      'common.system': '跟随系统',
      'common.light': '浅色',
      'common.dark': '深色',
      'settings.reader': '阅读器',
      'settings.appearance': '外观',
      'settings.network': '网络',
      'settings.downloads': '下载',
      'settings.app': '应用',
      'settings.about': '关于 / 调试',
      'settings.language': '语言',
      'settings.languageSubtitle': '选择应用界面显示语言。',
      'settings.themeMode': '主题模式',
      'settings.themeColor': '主题色',
      'settings.readerShowTapGuide': '显示点击提示',
      'settings.readerShowTapGuideSubtitle': '在右下角显示翻页和控制层提示。',
      'settings.prefetchPages': '预加载页数',
      'settings.prefetchPagesSubtitle': '在阅读器中提前预加载后续 {count} 页。',
      'settings.sourceIndexUrl': '图源索引地址',
      'settings.indexUrl': '索引地址',
      'settings.saveDownloadedCover': '保存下载封面',
      'settings.saveDownloadedCoverSubtitle': '将封面保存到本地下载库，供卡片和历史记录使用。',
      'settings.downloadDirectory': '下载目录',
      'settings.downloadDirectorySubtitle': '选择下载漫画和本地下载库的保存位置。',
      'settings.readerCacheDirectory': '阅读器缓存目录',
      'settings.readerCacheDirectorySubtitle': '选择阅读器图片缓存文件的存放位置。',
      'settings.openFolder': '打开文件夹',
      'settings.selectFolder': '选择文件夹',
      'settings.useDefaultPath': '使用默认路径',
      'settings.cacheSize': '缓存大小',
      'settings.cacheLimit': '缓存上限',
      'settings.cacheLimitSubtitle': '当前最多保留 {count} MB 阅读器缓存。',
      'settings.clearCache': '清理缓存',
      'settings.clearCacheSubtitle': '删除当前缓存目录中的所有阅读器缓存图片。',
      'settings.cacheCleared': '已清理阅读器缓存。',
      'settings.pathUpdated': '路径已更新。',
      'settings.pathUpdateFailed': '更新路径失败。',
      'settings.directoryOpenFailed': '无法打开该文件夹。',
      'settings.selectFolderFailed': '无法打开文件夹选择器。',
      'settings.downloadedComicsCount': '已保存 {count} 部漫画',
      'settings.installedSources': '已安装图源',
      'settings.installedSourcesCount': '当前已加载 {count} 个图源',
      'settings.readingHistory': '阅读历史',
      'settings.readingHistoryCount': '当前保存 {count} 条记录',
      'settings.resetSettings': '重置设置',
      'settings.resetSettingsSubtitle': '将 EZVenera 设置恢复到当前默认值。',
      'settings.resetDialogTitle': '重置设置',
      'settings.resetDialogBody': '要将当前 EZVenera 设置恢复为默认值吗？',
      'settings.aboutDescription':
          '一个更易维护的 Venera 简化版，专注于 Windows、Android、插件兼容与长期清晰的结构。',
      'settings.sourceRepository': '图源仓库',
      'settings.sourceRepositorySubtitle': 'EZVenera-config 是当前默认图源索引仓库。',
      'settings.github': 'GitHub',
      'settings.githubSubtitle': '在浏览器中打开 EZVenera 仓库。',
      'settings.linkOpenFailed': '无法在系统浏览器中打开该链接。',
      'language.system': '跟随系统',
      'language.english': 'English',
      'language.simplifiedChinese': '简体中文',
      'themeColor.teal': '青绿',
      'themeColor.amber': '琥珀',
      'themeColor.rose': '玫瑰',
      'themeColor.blue': '海蓝',
      'themeColor.forest': '森林',
    },
  };

  String _value(String key) {
    final languageMap =
        _localizedValues[locale.languageCode] ?? _localizedValues['en']!;
    return languageMap[key] ?? _localizedValues['en']![key] ?? key;
  }

  String navLabel(String key) => _value('nav.$key');

  String get localHistory => _value('local.history');
  String get localFavorites => _value('local.favorites');
  String get localDownloads => _value('local.downloads');
  String get localActiveTasks => _value('local.activeTasks');
  String get localDownloadedComics => _value('local.downloadedComics');
  String get localNoDownloads => _value('local.noDownloads');
  String get localNoDownloadsBody => _value('local.noDownloadsBody');
  String get localNoHistory => _value('local.noHistory');
  String get localNoHistoryBody => _value('local.noHistoryBody');
  String get localNoFavorites => _value('local.noFavorites');
  String get localNoFavoritesBody => _value('local.noFavoritesBody');
  String get localFavoriteMeta => _value('local.favoriteMeta');
  String get open => _value('common.open');
  String get delete => _value('common.delete');
  String get save => _value('common.save');
  String get reset => _value('common.reset');
  String get cancel => _value('common.cancel');
  String get systemLabel => _value('common.system');
  String get light => _value('common.light');
  String get dark => _value('common.dark');
  String get settingsReader => _value('settings.reader');
  String get settingsAppearance => _value('settings.appearance');
  String get settingsNetwork => _value('settings.network');
  String get settingsDownloads => _value('settings.downloads');
  String get settingsApp => _value('settings.app');
  String get settingsAbout => _value('settings.about');
  String get settingsLanguage => _value('settings.language');
  String get settingsLanguageSubtitle => _value('settings.languageSubtitle');
  String get settingsThemeMode => _value('settings.themeMode');
  String get settingsThemeColor => _value('settings.themeColor');
  String get settingsReaderShowTapGuide =>
      _value('settings.readerShowTapGuide');
  String get settingsReaderShowTapGuideSubtitle =>
      _value('settings.readerShowTapGuideSubtitle');
  String get settingsPrefetchPages => _value('settings.prefetchPages');
  String settingsPrefetchPagesSubtitle(int count) =>
      _value('settings.prefetchPagesSubtitle').replaceAll('{count}', '$count');
  String get settingsSourceIndexUrl => _value('settings.sourceIndexUrl');
  String get settingsIndexUrl => _value('settings.indexUrl');
  String get settingsSaveDownloadedCover =>
      _value('settings.saveDownloadedCover');
  String get settingsSaveDownloadedCoverSubtitle =>
      _value('settings.saveDownloadedCoverSubtitle');
  String get settingsDownloadDirectory => _value('settings.downloadDirectory');
  String get settingsDownloadDirectorySubtitle =>
      _value('settings.downloadDirectorySubtitle');
  String get settingsReaderCacheDirectory =>
      _value('settings.readerCacheDirectory');
  String get settingsReaderCacheDirectorySubtitle =>
      _value('settings.readerCacheDirectorySubtitle');
  String get settingsOpenFolder => _value('settings.openFolder');
  String get settingsSelectFolder => _value('settings.selectFolder');
  String get settingsUseDefaultPath => _value('settings.useDefaultPath');
  String get settingsCacheSize => _value('settings.cacheSize');
  String get settingsCacheLimit => _value('settings.cacheLimit');
  String settingsCacheLimitSubtitle(int count) =>
      _value('settings.cacheLimitSubtitle').replaceAll('{count}', '$count');
  String get settingsClearCache => _value('settings.clearCache');
  String get settingsClearCacheSubtitle =>
      _value('settings.clearCacheSubtitle');
  String get settingsCacheCleared => _value('settings.cacheCleared');
  String get settingsPathUpdated => _value('settings.pathUpdated');
  String get settingsPathUpdateFailed => _value('settings.pathUpdateFailed');
  String get settingsDirectoryOpenFailed =>
      _value('settings.directoryOpenFailed');
  String get settingsSelectFolderFailed =>
      _value('settings.selectFolderFailed');
  String settingsDownloadedComicsCount(int count) =>
      _value('settings.downloadedComicsCount').replaceAll('{count}', '$count');
  String get settingsInstalledSources => _value('settings.installedSources');
  String settingsInstalledSourcesCount(int count) =>
      _value('settings.installedSourcesCount').replaceAll('{count}', '$count');
  String get settingsReadingHistory => _value('settings.readingHistory');
  String settingsReadingHistoryCount(int count) =>
      _value('settings.readingHistoryCount').replaceAll('{count}', '$count');
  String get settingsResetSettings => _value('settings.resetSettings');
  String get settingsResetSettingsSubtitle =>
      _value('settings.resetSettingsSubtitle');
  String get settingsResetDialogTitle => _value('settings.resetDialogTitle');
  String get settingsResetDialogBody => _value('settings.resetDialogBody');
  String get settingsAboutDescription => _value('settings.aboutDescription');
  String get settingsSourceRepository => _value('settings.sourceRepository');
  String get settingsSourceRepositorySubtitle =>
      _value('settings.sourceRepositorySubtitle');
  String get settingsGithub => _value('settings.github');
  String get settingsGithubSubtitle => _value('settings.githubSubtitle');
  String get settingsLinkOpenFailed => _value('settings.linkOpenFailed');

  String languageLabel(AppLanguageOption option) {
    return switch (option) {
      AppLanguageOption.system => _value('language.system'),
      AppLanguageOption.english => _value('language.english'),
      AppLanguageOption.simplifiedChinese => _value(
        'language.simplifiedChinese',
      ),
    };
  }

  String themePresetLabel(AppThemePreset preset) {
    return switch (preset) {
      AppThemePreset.teal => _value('themeColor.teal'),
      AppThemePreset.amber => _value('themeColor.amber'),
      AppThemePreset.rose => _value('themeColor.rose'),
      AppThemePreset.blue => _value('themeColor.blue'),
      AppThemePreset.forest => _value('themeColor.forest'),
    };
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}
