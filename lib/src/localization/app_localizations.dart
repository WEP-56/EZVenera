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
      'local.library': 'Library',
      'local.libraryBadge': 'Local',
      'local.systemFolders': 'Built-in',
      'local.folders': 'Comic Folders',
      'local.folderMenu': 'Folders',
      'local.addFolder': 'Add Folder',
      'local.folderAdded': 'Folder added.',
      'local.folderRemoved': 'Folder removed.',
      'local.folderPickerFailed': 'Failed to open folder selector.',
      'local.removeFolderTitle': 'Remove Folder',
      'local.removeFolderBody':
          'Remove "{name}" from the local page? Files on disk will not be deleted.',
      'local.noFolders': 'No comic folders yet',
      'local.noFoldersBody':
          'Add a folder that contains comic directories or image files.',
      'local.noFolderComics': 'No comics found',
      'local.noFolderComicsBody':
          'Each comic should be a folder with images or chapter subfolders.',
      'local.folderMissing': 'Folder unavailable',
      'local.folderMissingBody':
          'The selected directory no longer exists or cannot be read.',
      'local.refreshFolder': 'Refresh Folder',
      'local.expandSidebar': 'Expand sidebar',
      'local.collapseSidebar': 'Collapse sidebar',
      'local.comicsCount': '{count} comic(s)',
      'local.chaptersPages': '{chapters} chapter(s) · {pages} page(s)',
      'reader.settings': 'Reader Settings',
      'reader.tapToTurn': 'Tap to turn pages',
      'reader.reverseTapToTurn': 'Reverse tap zones',
      'reader.doubleTapZoom': 'Double-tap zoom',
      'reader.pageAnimation': 'Page animation',
      'reader.autoPageInterval': 'Auto page interval',
      'reader.seconds': '{count}s',
      'reader.downloadCurrent': 'Download Current Chapter',
      'reader.downloadAll': 'Download All Chapters',
      'reader.downloadStarted': 'Download started for {title}',
      'reader.autoPageOn': 'Auto page on',
      'reader.autoPageOff': 'Auto page off',
      'reader.fullscreen': 'Fullscreen',
      'reader.exitFullscreen': 'Exit fullscreen',
      'reader.download': 'Download',
      'settings.checkUpdate': 'Check for Updates',
      'settings.updateDialogTitle': 'Update Available',
      'settings.noUpdate': 'You are already on the latest version.',
      'settings.updateNow': 'Download Update',
      'settings.later': 'Later',
      'settings.downloadingUpdate': 'Downloading update...',
      'settings.downloadComplete': 'Download completed.',
      'settings.installNow': 'Install Now',
      'settings.updateFailed': 'Failed to check or download the update.',
      'settings.latestVersionLabel': 'Latest version: {version}',
      'settings.installFailed':
          'Failed to launch the installer. You can open it manually at {path}.',
      'settings.enableInstallFromUnknownSources':
          'Allow this app to install packages in system settings, then try again.',
      'comicDisplay.showList': 'Switch to List View',
      'comicDisplay.showGrid': 'Switch to Grid View',
      'reader.direction': 'Reading Direction',
      'reader.direction.leftToRight': 'Left to Right',
      'reader.direction.rightToLeft': 'Right to Left',
      'reader.direction.topToBottom': 'Top to Bottom',
      'reader.volumeKeys': 'Volume-key page turning',
      'reader.volumeKeysSubtitle':
          'Use the device volume buttons to flip pages while reading.',
      'sources.addTitle': 'Add comic source',
      'sources.addSubtitle':
          'Install a source by raw URL or from repository index',
      'sources.urlLabel': 'Source URL',
      'sources.urlHint': 'https://example.com/source.js',
      'sources.install': 'Install',
      'sources.comicSourceList': 'Comic Source List',
      'sources.installLocal': 'Install Local',
      'sources.reload': 'Reload',
      'sources.installed': 'Installed {name}',
      'sources.installFailed': 'Failed to install source',
      'sources.reloaded': 'Sources reloaded',
      'sources.reloadFailed': 'Failed to reload sources',
      'sources.noSources': 'No sources installed',
      'sources.noSourcesBody':
          'Install a source config first. Existing Venera source files are supported as long as they stay within the retained EZVenera capability set.',
      'sources.settings': 'Settings',
      'sources.account': 'Account',
      'sources.path': 'Path',
      'sources.update': 'Update',
      'sources.delete': 'Delete',
      'sources.updated': 'Updated {name}',
      'sources.deleteTitle': 'Delete Source',
      'sources.deleteBody': 'Delete {name}?',
      'sources.deleted': 'Deleted {name}',
      'sources.loggedIn': 'Logged in',
      'sources.notLoggedIn': 'Not logged in',
      'sources.passwordLogin': 'Password login',
      'sources.cookieLogin': 'Cookie login',
      'sources.webLoginAvailable': 'Web login URL available',
      'sources.logIn': 'Log in',
      'sources.cookies': 'Cookies',
      'sources.webview': 'Webview',
      'sources.logOut': 'Log out',
      'sources.reLogin': 'Re-login',
      'sources.username': 'Username',
      'sources.password': 'Password',
      'sources.continueAction': 'Continue',
      'sources.cookieLoginTitle': 'Cookie Login',
      'sources.invalidCookies': 'Invalid cookies',
      'sources.loginSuccess': 'Login successful',
      'sources.cookieLoginSuccess': 'Cookie login successful',
      'sources.reloginSuccess': 'Re-login successful',
      'sources.webviewLoginSuccess': 'Webview login successful',
      'sources.webviewNoStatus':
          'This source does not expose login status detection.',
      'sources.invalidValue': 'Invalid value',
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
  String get localLibrary => isChinese ? '漫画库' : _value('local.library');
  String get localLibraryBadge =>
      isChinese ? '本地' : _value('local.libraryBadge');
  String get localSystemFolders =>
      isChinese ? '内置目录' : _value('local.systemFolders');
  String get localFolders => isChinese ? '漫画文件夹' : _value('local.folders');
  String get localFolderMenu => isChinese ? '文件夹' : _value('local.folderMenu');
  String get localAddFolder => isChinese ? '添加文件夹' : _value('local.addFolder');
  String get localFolderAdded =>
      isChinese ? '已添加文件夹。' : _value('local.folderAdded');
  String get localFolderRemoved =>
      isChinese ? '已移除文件夹。' : _value('local.folderRemoved');
  String get localFolderPickerFailed =>
      isChinese ? '无法打开文件夹选择器。' : _value('local.folderPickerFailed');
  String get localRemoveFolderTitle =>
      isChinese ? '移除文件夹' : _value('local.removeFolderTitle');
  String localRemoveFolderBody(String name) =>
      (isChinese
              ? '要从本地页面移除“{name}”吗？不会删除磁盘上的文件。'
              : _value('local.removeFolderBody'))
          .replaceAll('{name}', name);
  String get localNoFolders =>
      isChinese ? '还没有漫画文件夹' : _value('local.noFolders');
  String get localNoFoldersBody =>
      isChinese ? '添加一个包含漫画目录或图片文件的文件夹。' : _value('local.noFoldersBody');
  String get localNoFolderComics =>
      isChinese ? '未找到漫画' : _value('local.noFolderComics');
  String get localNoFolderComicsBody => isChinese
      ? '每部漫画应为一个目录，目录内包含图片或章节子目录。'
      : _value('local.noFolderComicsBody');
  String get localFolderMissing =>
      isChinese ? '文件夹不可用' : _value('local.folderMissing');
  String get localFolderMissingBody =>
      isChinese ? '所选目录已不存在，或当前无法读取。' : _value('local.folderMissingBody');
  String get localRefreshFolder =>
      isChinese ? '刷新文件夹' : _value('local.refreshFolder');
  String get localExpandSidebar =>
      isChinese ? '展开侧栏' : _value('local.expandSidebar');
  String get localCollapseSidebar =>
      isChinese ? '收起侧栏' : _value('local.collapseSidebar');
  String localComicsCount(int count) =>
      (isChinese ? '{count} 部漫画' : _value('local.comicsCount')).replaceAll(
        '{count}',
        '$count',
      );
  String localChaptersPages(int chapters, int pages) =>
      (isChinese ? '{chapters} 章 · {pages} 页' : _value('local.chaptersPages'))
          .replaceAll('{chapters}', '$chapters')
          .replaceAll('{pages}', '$pages');
  String get readerSettings => isChinese ? '阅读设置' : _value('reader.settings');
  String get readerTapToTurn => isChinese ? '点击翻页' : _value('reader.tapToTurn');
  String get readerReverseTapToTurn =>
      isChinese ? '反转点击翻页' : _value('reader.reverseTapToTurn');
  String get readerDoubleTapZoom =>
      isChinese ? '双击缩放' : _value('reader.doubleTapZoom');
  String get readerPageAnimation =>
      isChinese ? '页面动画' : _value('reader.pageAnimation');
  String get readerAutoPageInterval =>
      isChinese ? '自动翻页间隔' : _value('reader.autoPageInterval');
  String readerSeconds(num count) =>
      (isChinese ? '{count}秒' : _value('reader.seconds')).replaceAll(
        '{count}',
        count.toString(),
      );
  String get readerDownloadCurrent =>
      isChinese ? '下载当前章节' : _value('reader.downloadCurrent');
  String get readerDownloadAll =>
      isChinese ? '下载全部章节' : _value('reader.downloadAll');
  String readerDownloadStarted(String title) =>
      (isChinese ? '开始下载：{title}' : _value('reader.downloadStarted'))
          .replaceAll('{title}', title);
  String get readerAutoPageOn =>
      isChinese ? '自动翻页已开启' : _value('reader.autoPageOn');
  String get readerAutoPageOff =>
      isChinese ? '自动翻页已关闭' : _value('reader.autoPageOff');
  String get readerFullscreen => isChinese ? '全屏' : _value('reader.fullscreen');
  String get readerExitFullscreen =>
      isChinese ? '退出全屏' : _value('reader.exitFullscreen');
  String get readerDownload => isChinese ? '下载' : _value('reader.download');
  String get settingsCheckUpdate =>
      isChinese ? '检查更新' : _value('settings.checkUpdate');
  String get settingsUpdateDialogTitle =>
      isChinese ? '发现新版本' : _value('settings.updateDialogTitle');
  String get settingsNoUpdate =>
      isChinese ? '当前已经是最新版本。' : _value('settings.noUpdate');
  String get settingsUpdateNow =>
      isChinese ? '下载更新' : _value('settings.updateNow');
  String get settingsLater => isChinese ? '稍后' : _value('settings.later');
  String get settingsDownloadingUpdate =>
      isChinese ? '正在下载更新...' : _value('settings.downloadingUpdate');
  String get settingsDownloadComplete =>
      isChinese ? '下载完成。' : _value('settings.downloadComplete');
  String get settingsInstallNow =>
      isChinese ? '立即安装' : _value('settings.installNow');
  String get settingsUpdateFailed =>
      isChinese ? '检查或下载更新失败。' : _value('settings.updateFailed');
  String settingsLatestVersionLabel(String version) =>
      (isChinese ? '最新版本：{version}' : _value('settings.latestVersionLabel'))
          .replaceAll('{version}', version);
  String settingsInstallFailed(String path) =>
      (isChinese
              ? '无法启动安装程序，可以手动在 {path} 打开。'
              : _value('settings.installFailed'))
          .replaceAll('{path}', path);
  String get settingsEnableInstallFromUnknownSources => isChinese
      ? '请在系统设置中允许本应用安装应用包后再试。'
      : _value('settings.enableInstallFromUnknownSources');
  String get comicDisplayShowList =>
      isChinese ? '切换为列表视图' : _value('comicDisplay.showList');
  String get comicDisplayShowGrid =>
      isChinese ? '切换为网格视图' : _value('comicDisplay.showGrid');
  String get readerDirection =>
      isChinese ? '阅读方向' : _value('reader.direction');
  String get readerDirectionLeftToRight =>
      isChinese ? '从左至右' : _value('reader.direction.leftToRight');
  String get readerDirectionRightToLeft =>
      isChinese ? '从右至左' : _value('reader.direction.rightToLeft');
  String get readerDirectionTopToBottom =>
      isChinese ? '从上至下' : _value('reader.direction.topToBottom');
  String get readerVolumeKeys =>
      isChinese ? '音量键翻页' : _value('reader.volumeKeys');
  String get readerVolumeKeysSubtitle => isChinese
      ? '使用手机音量上下键翻页（仅 Android）。'
      : _value('reader.volumeKeysSubtitle');
  String get sourcesAddTitle =>
      isChinese ? '添加图源' : _value('sources.addTitle');
  String get sourcesAddSubtitle => isChinese
      ? '通过链接或仓库索引安装一个图源。'
      : _value('sources.addSubtitle');
  String get sourcesUrlLabel =>
      isChinese ? '图源 URL' : _value('sources.urlLabel');
  String get sourcesUrlHint => _value('sources.urlHint');
  String get sourcesInstall =>
      isChinese ? '安装' : _value('sources.install');
  String get sourcesComicSourceList =>
      isChinese ? '图源列表' : _value('sources.comicSourceList');
  String get sourcesInstallLocal =>
      isChinese ? '本地安装' : _value('sources.installLocal');
  String get sourcesReload =>
      isChinese ? '重新加载' : _value('sources.reload');
  String sourcesInstalled(String name) =>
      (isChinese ? '已安装 {name}' : _value('sources.installed'))
          .replaceAll('{name}', name);
  String get sourcesInstallFailed =>
      isChinese ? '安装图源失败' : _value('sources.installFailed');
  String get sourcesReloaded =>
      isChinese ? '图源已重新加载' : _value('sources.reloaded');
  String get sourcesReloadFailed =>
      isChinese ? '重新加载失败' : _value('sources.reloadFailed');
  String get sourcesNoSources =>
      isChinese ? '尚未安装图源' : _value('sources.noSources');
  String get sourcesNoSourcesBody => isChinese
      ? '先安装一个图源配置。现有的 Venera 图源文件只要使用了 EZVenera 支持的能力子集，都可以直接安装。'
      : _value('sources.noSourcesBody');
  String get sourcesSettings =>
      isChinese ? '设置' : _value('sources.settings');
  String get sourcesAccount =>
      isChinese ? '账号' : _value('sources.account');
  String get sourcesPath => isChinese ? '路径' : _value('sources.path');
  String get sourcesUpdate =>
      isChinese ? '更新' : _value('sources.update');
  String get sourcesDelete =>
      isChinese ? '删除' : _value('sources.delete');
  String sourcesUpdated(String name) =>
      (isChinese ? '已更新 {name}' : _value('sources.updated'))
          .replaceAll('{name}', name);
  String get sourcesDeleteTitle =>
      isChinese ? '删除图源' : _value('sources.deleteTitle');
  String sourcesDeleteBody(String name) =>
      (isChinese ? '确定要删除 {name} 吗？' : _value('sources.deleteBody'))
          .replaceAll('{name}', name);
  String sourcesDeleted(String name) =>
      (isChinese ? '已删除 {name}' : _value('sources.deleted'))
          .replaceAll('{name}', name);
  String get sourcesLoggedIn =>
      isChinese ? '已登录' : _value('sources.loggedIn');
  String get sourcesNotLoggedIn =>
      isChinese ? '未登录' : _value('sources.notLoggedIn');
  String get sourcesPasswordLogin =>
      isChinese ? '密码登录' : _value('sources.passwordLogin');
  String get sourcesCookieLogin =>
      isChinese ? 'Cookie 登录' : _value('sources.cookieLogin');
  String get sourcesWebLoginAvailable =>
      isChinese ? '支持网页登录' : _value('sources.webLoginAvailable');
  String get sourcesLogIn =>
      isChinese ? '登录' : _value('sources.logIn');
  String get sourcesCookies =>
      isChinese ? 'Cookie' : _value('sources.cookies');
  String get sourcesWebview =>
      isChinese ? '浏览器登录' : _value('sources.webview');
  String get sourcesLogOut =>
      isChinese ? '退出登录' : _value('sources.logOut');
  String get sourcesReLogin =>
      isChinese ? '重新登录' : _value('sources.reLogin');
  String get sourcesUsername =>
      isChinese ? '账号' : _value('sources.username');
  String get sourcesPassword =>
      isChinese ? '密码' : _value('sources.password');
  String get sourcesContinue =>
      isChinese ? '继续' : _value('sources.continueAction');
  String get sourcesCookieLoginTitle =>
      isChinese ? 'Cookie 登录' : _value('sources.cookieLoginTitle');
  String get sourcesInvalidCookies =>
      isChinese ? 'Cookie 无效' : _value('sources.invalidCookies');
  String get sourcesLoginSuccess =>
      isChinese ? '登录成功' : _value('sources.loginSuccess');
  String get sourcesCookieLoginSuccess =>
      isChinese ? 'Cookie 登录成功' : _value('sources.cookieLoginSuccess');
  String get sourcesReloginSuccess =>
      isChinese ? '重新登录成功' : _value('sources.reloginSuccess');
  String get sourcesWebviewLoginSuccess =>
      isChinese ? '浏览器登录成功' : _value('sources.webviewLoginSuccess');
  String get sourcesWebviewNoStatus => isChinese
      ? '此图源未提供登录状态检测。'
      : _value('sources.webviewNoStatus');
  String get sourcesInvalidValue =>
      isChinese ? '值无效' : _value('sources.invalidValue');
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
