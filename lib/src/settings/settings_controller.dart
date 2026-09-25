import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../localization/app_localizations.dart';
import '../utils/json_file_store.dart';

/// Layout mode for browsing results such as search output and category lists.
enum ComicDisplayMode { grid, list }

/// Reading orientation / direction for the comic reader.
///
/// * [galleryLeftToRight] - horizontal paging with left-to-right flow (western
///   comics, default for most sources).
/// * [galleryRightToLeft] - horizontal paging with right-to-left flow
///   (Japanese manga).
/// * [continuousTopToBottom] - vertical paging with top-to-bottom flow
///   (webtoons).
enum ReaderPageMode {
  galleryLeftToRight,
  galleryRightToLeft,
  continuousTopToBottom,
}

/// Proxy selection for every outbound HTTP(S) request.
///
/// * [system] - follow the system/environment proxy (default).
/// * [custom] - route through the user-provided proxy URL.
/// * [off] - force direct connections, ignoring any system proxy.
enum ProxyMode { system, custom, off }

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  static const defaultSourceIndexUrls = <String>[
    'https://raw.githubusercontent.com/WEP-56/EZvenera-config/main/index.json',
    'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json',
  ];
  static const defaultSourceIndexUrl =
      'https://raw.githubusercontent.com/WEP-56/EZvenera-config/main/index.json';

  bool _initialized = false;
  ThemeMode _themeMode = ThemeMode.system;
  List<String> _sourceIndexUrls = List<String>.of(defaultSourceIndexUrls);
  String _sourceIndexUrl = defaultSourceIndexUrl;
  bool _readerShowTapGuide = true;
  int _readerPrefetchCount = 3;
  bool _readerEnableTapToTurnPages = true;
  bool _readerReverseTapToTurnPages = false;
  bool _readerEnableDoubleTapZoom = true;
  bool _readerEnablePageAnimation = true;
  double _readerAutoPageIntervalSeconds = 5;
  ReaderPageMode _readerPageMode = ReaderPageMode.galleryLeftToRight;
  double _readerVerticalMarginPercent = 0;
  bool _readerEnableVolumeKeys = true;
  bool _readerHorizontalContinuous = false;
  bool _readerShowChapterEdgeButtons = true;
  ComicDisplayMode _comicDisplayMode = ComicDisplayMode.grid;
  int _searchHistoryLimit = 30;
  bool _downloadSaveCover = true;
  AppLanguageOption _language = AppLanguageOption.system;
  AppThemePreset _themePreset = AppThemePreset.teal;
  String? _downloadDirectoryPath;
  String? _readerCacheDirectoryPath;
  String _webDavUrl = '';
  String _webDavUsername = '';
  String _webDavPassword = '';
  bool _webDavAutoSync = false;
  ProxyMode _proxyMode = ProxyMode.system;
  String _proxyUrl = '';
  bool _einkMode = false;
  bool _einkHighContrast = true;
  bool _einkFullRefreshHint = true;
  int _dataVersion = 0;
  int _readerCacheLimitMb = 512;
  File? _file;
  JsonFileStore? _store;

  ThemeMode get themeMode => _themeMode;
  List<String> get sourceIndexUrls =>
      List<String>.unmodifiable(_sourceIndexUrls);
  String get sourceIndexUrl => _sourceIndexUrl;
  bool get readerShowTapGuide => _readerShowTapGuide;
  int get readerPrefetchCount => _readerPrefetchCount;
  bool get readerEnableTapToTurnPages => _readerEnableTapToTurnPages;
  bool get readerReverseTapToTurnPages => _readerReverseTapToTurnPages;
  bool get readerEnableDoubleTapZoom => _readerEnableDoubleTapZoom;
  bool get readerEnablePageAnimation => _readerEnablePageAnimation;
  double get readerAutoPageIntervalSeconds => _readerAutoPageIntervalSeconds;
  ReaderPageMode get readerPageMode => _readerPageMode;
  double get readerVerticalMarginPercent => _readerVerticalMarginPercent;
  bool get readerEnableVolumeKeys => _readerEnableVolumeKeys;
  bool get readerHorizontalContinuous => _readerHorizontalContinuous;
  bool get readerShowChapterEdgeButtons => _readerShowChapterEdgeButtons;
  ComicDisplayMode get comicDisplayMode => _comicDisplayMode;
  int get searchHistoryLimit => _searchHistoryLimit;
  bool get downloadSaveCover => _downloadSaveCover;
  AppLanguageOption get language => _language;
  AppThemePreset get themePreset => _themePreset;
  String? get downloadDirectoryPath => _downloadDirectoryPath;
  String? get readerCacheDirectoryPath => _readerCacheDirectoryPath;
  String get webDavUrl => _webDavUrl;
  String get webDavUsername => _webDavUsername;
  String get webDavPassword => _webDavPassword;
  bool get hasWebDavConfig => _webDavUrl.trim().isNotEmpty;
  bool get webDavAutoSync => _webDavAutoSync;
  ProxyMode get proxyMode => _proxyMode;
  String get proxyUrl => _proxyUrl;

  /// Proxy URL safe for display and logs — credentials stripped (ADR-NW-2).
  String get proxyDisplayUrl => _sanitizeStoredProxyUrl(_proxyUrl);

  /// E-Ink friendly mode: no animations, optional high-contrast theme
  /// (REQ-001..004). Defaults to off so LCD/OLED users see no change.
  bool get einkMode => _einkMode;
  bool get einkHighContrast => _einkHighContrast;
  bool get einkFullRefreshHint => _einkFullRefreshHint;
  int get dataVersion => _dataVersion;
  int get readerCacheLimitMb => _readerCacheLimitMb;
  Locale? get locale => switch (_language) {
    AppLanguageOption.system => null,
    AppLanguageOption.english => const Locale('en'),
    AppLanguageOption.simplifiedChinese => const Locale('zh', 'CN'),
  };
  Color get themeSeedColor => switch (_themePreset) {
    AppThemePreset.teal => const Color(0xFF0F766E),
    AppThemePreset.amber => const Color(0xFFB45309),
    AppThemePreset.rose => const Color(0xFFBE185D),
    AppThemePreset.blue => const Color(0xFF1D4ED8),
    AppThemePreset.forest => const Color(0xFF3F6212),
  };
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'settings'));
    await root.create(recursive: true);
    _file = File(p.join(root.path, 'app_settings.json'));
    _store = JsonFileStore(_file!);

    // Corrupted or missing files yield an empty map: we fall back to
    // defaults and immediately rewrite a healthy file (REQ-011).
    final decoded = await _store!.read();
    if (decoded.isNotEmpty) {
      final needsSourceIndexMigration = decoded['sourceIndexUrls'] is! List;
      _themeMode = _parseThemeMode(decoded['themeMode']?.toString());
        _loadSourceIndexSettings(decoded);
        _readerShowTapGuide = decoded['readerShowTapGuide'] != false;
        _readerPrefetchCount = _parsePrefetchCount(
          (decoded['readerPrefetchCount'] as num?)?.toInt(),
        );
        _readerEnableTapToTurnPages =
            decoded['readerEnableTapToTurnPages'] != false;
        _readerReverseTapToTurnPages =
            decoded['readerReverseTapToTurnPages'] == true;
        _readerEnableDoubleTapZoom =
            decoded['readerEnableDoubleTapZoom'] != false;
        _readerEnablePageAnimation =
            decoded['readerEnablePageAnimation'] != false;
        _readerAutoPageIntervalSeconds = _parseAutoPageIntervalSeconds(
          (decoded['readerAutoPageIntervalSeconds'] as num?)?.toDouble(),
        );
        _readerPageMode = _parseReaderPageMode(
          decoded['readerPageMode']?.toString(),
        );
        _readerVerticalMarginPercent = _parseReaderVerticalMarginPercent(
          (decoded['readerVerticalMarginPercent'] as num?)?.toDouble(),
        );
        _readerEnableVolumeKeys = decoded['readerEnableVolumeKeys'] != false;
        _readerHorizontalContinuous =
            decoded['readerHorizontalContinuous'] == true;
        _readerShowChapterEdgeButtons =
            decoded['readerShowChapterEdgeButtons'] != false;
        _comicDisplayMode = _parseComicDisplayMode(
          decoded['comicDisplayMode']?.toString(),
        );
        _searchHistoryLimit = _parseSearchHistoryLimit(
          (decoded['searchHistoryLimit'] as num?)?.toInt(),
        );
        _downloadSaveCover = decoded['downloadSaveCover'] != false;
        _language = _parseLanguage(decoded['language']?.toString());
        _themePreset = _parseThemePreset(decoded['themePreset']?.toString());
        _downloadDirectoryPath = _normalizeDirectoryPath(
          decoded['downloadDirectoryPath']?.toString(),
        );
        _readerCacheDirectoryPath = _normalizeDirectoryPath(
          decoded['readerCacheDirectoryPath']?.toString(),
        );
        _webDavUrl = decoded['webDavUrl']?.toString() ?? '';
        _webDavUsername = decoded['webDavUsername']?.toString() ?? '';
        _webDavPassword = decoded['webDavPassword']?.toString() ?? '';
        _webDavAutoSync = decoded['webDavAutoSync'] == true;
        _proxyMode = _parseProxyMode(decoded['proxyMode']?.toString());
        _proxyUrl = _sanitizeStoredProxyUrl(
          decoded['proxyUrl']?.toString() ?? '',
        );
        _einkMode = decoded['einkMode'] == true;
        _einkHighContrast = decoded['einkHighContrast'] != false;
        _einkFullRefreshHint = decoded['einkFullRefreshHint'] != false;
        _dataVersion = (decoded['dataVersion'] as num?)?.toInt() ?? 0;
        if (_dataVersion < 0) {
          _dataVersion = 0;
        }
        _readerCacheLimitMb = _parseCacheLimitMb(
          (decoded['readerCacheLimitMb'] as num?)?.toInt(),
        );
        if (needsSourceIndexMigration) {
          await _persist();
        }
    } else {
      await _persist();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setSourceIndexUrl(String value) async {
    final normalized = value.trim().isEmpty
        ? defaultSourceIndexUrl
        : value.trim();
    if (_sourceIndexUrl == normalized) {
      return;
    }
    if (!_sourceIndexUrls.contains(normalized)) {
      _sourceIndexUrls = <String>[..._sourceIndexUrls, normalized];
    }
    _sourceIndexUrl = normalized;
    await _persist();
    notifyListeners();
  }

  Future<bool> addSourceIndexUrl(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || _sourceIndexUrls.contains(normalized)) {
      return false;
    }
    _sourceIndexUrls = <String>[..._sourceIndexUrls, normalized];
    _sourceIndexUrl = normalized;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> removeSourceIndexUrl(String value) async {
    if (_sourceIndexUrls.length <= 1 || !_sourceIndexUrls.contains(value)) {
      return;
    }
    final removedIndex = _sourceIndexUrls.indexOf(value);
    _sourceIndexUrls = _sourceIndexUrls.where((item) => item != value).toList();
    if (_sourceIndexUrl == value) {
      _sourceIndexUrl =
          _sourceIndexUrls[removedIndex.clamp(0, _sourceIndexUrls.length - 1)];
    }
    await _persist();
    notifyListeners();
  }

  Future<void> resetSourceIndexUrls() async {
    _sourceIndexUrls = List<String>.of(defaultSourceIndexUrls);
    _sourceIndexUrl = defaultSourceIndexUrl;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderShowTapGuide(bool value) async {
    if (_readerShowTapGuide == value) {
      return;
    }
    _readerShowTapGuide = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderPrefetchCount(int value) async {
    final normalized = _parsePrefetchCount(value);
    if (_readerPrefetchCount == normalized) {
      return;
    }
    _readerPrefetchCount = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderEnableTapToTurnPages(bool value) async {
    if (_readerEnableTapToTurnPages == value) {
      return;
    }
    _readerEnableTapToTurnPages = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderReverseTapToTurnPages(bool value) async {
    if (_readerReverseTapToTurnPages == value) {
      return;
    }
    _readerReverseTapToTurnPages = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderEnableDoubleTapZoom(bool value) async {
    if (_readerEnableDoubleTapZoom == value) {
      return;
    }
    _readerEnableDoubleTapZoom = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderEnablePageAnimation(bool value) async {
    if (_readerEnablePageAnimation == value) {
      return;
    }
    _readerEnablePageAnimation = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderAutoPageIntervalSeconds(double value) async {
    final normalized = _parseAutoPageIntervalSeconds(value);
    if (_readerAutoPageIntervalSeconds == normalized) {
      return;
    }
    _readerAutoPageIntervalSeconds = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderPageMode(ReaderPageMode value) async {
    if (_readerPageMode == value) {
      return;
    }
    _readerPageMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderVerticalMarginPercent(double value) async {
    final normalized = _parseReaderVerticalMarginPercent(value);
    if (_readerVerticalMarginPercent == normalized) {
      return;
    }
    _readerVerticalMarginPercent = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderEnableVolumeKeys(bool value) async {
    if (_readerEnableVolumeKeys == value) {
      return;
    }
    _readerEnableVolumeKeys = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderHorizontalContinuous(bool value) async {
    if (_readerHorizontalContinuous == value) {
      return;
    }
    _readerHorizontalContinuous = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderShowChapterEdgeButtons(bool value) async {
    if (_readerShowChapterEdgeButtons == value) {
      return;
    }
    _readerShowChapterEdgeButtons = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setComicDisplayMode(ComicDisplayMode value) async {
    if (_comicDisplayMode == value) {
      return;
    }
    _comicDisplayMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setSearchHistoryLimit(int value) async {
    final normalized = _parseSearchHistoryLimit(value);
    if (_searchHistoryLimit == normalized) {
      return;
    }
    _searchHistoryLimit = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setDownloadSaveCover(bool value) async {
    if (_downloadSaveCover == value) {
      return;
    }
    _downloadSaveCover = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguageOption value) async {
    if (_language == value) {
      return;
    }
    _language = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setThemePreset(AppThemePreset value) async {
    if (_themePreset == value) {
      return;
    }
    _themePreset = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setDownloadDirectoryPath(String? value) async {
    final normalized = _normalizeDirectoryPath(value);
    if (_downloadDirectoryPath == normalized) {
      return;
    }
    _downloadDirectoryPath = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderCacheDirectoryPath(String? value) async {
    final normalized = _normalizeDirectoryPath(value);
    if (_readerCacheDirectoryPath == normalized) {
      return;
    }
    _readerCacheDirectoryPath = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setReaderCacheLimitMb(int value) async {
    final normalized = _parseCacheLimitMb(value);
    if (_readerCacheLimitMb == normalized) {
      return;
    }
    _readerCacheLimitMb = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    final normalizedUrl = url.trim();
    final normalizedUsername = username.trim();
    if (_webDavUrl == normalizedUrl &&
        _webDavUsername == normalizedUsername &&
        _webDavPassword == password) {
      return;
    }
    _webDavUrl = normalizedUrl;
    _webDavUsername = normalizedUsername;
    _webDavPassword = password;
    // Clearing credentials also turns off auto-sync (mirrors upstream).
    if (normalizedUrl.isEmpty) {
      _webDavAutoSync = false;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setWebDavAutoSync(bool value) async {
    if (_webDavAutoSync == value) {
      return;
    }
    _webDavAutoSync = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setProxyMode(ProxyMode value) async {
    if (_proxyMode == value) {
      return;
    }
    _proxyMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setProxyUrl(String value) async {
    final normalized = value.trim();
    if (_proxyUrl == normalized) {
      return;
    }
    _proxyUrl = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> setEinkMode(bool value) async {
    if (_einkMode == value) {
      return;
    }
    _einkMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setEinkHighContrast(bool value) async {
    if (_einkHighContrast == value) {
      return;
    }
    _einkHighContrast = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setEinkFullRefreshHint(bool value) async {
    if (_einkFullRefreshHint == value) {
      return;
    }
    _einkFullRefreshHint = value;
    await _persist();
    notifyListeners();
  }

  /// Bumps the WebDAV sync counter (upstream `dataVersion`) before upload.
  Future<int> incrementDataVersion() async {
    _dataVersion += 1;
    await _persist();
    notifyListeners();
    return _dataVersion;
  }

  Map<String, dynamic> toBackupJson() {
    return <String, dynamic>{
      'themeMode': _themeMode.name,
      'sourceIndexUrls': _sourceIndexUrls,
      'sourceIndexUrl': _sourceIndexUrl,
      'readerShowTapGuide': _readerShowTapGuide,
      'readerPrefetchCount': _readerPrefetchCount,
      'readerEnableTapToTurnPages': _readerEnableTapToTurnPages,
      'readerReverseTapToTurnPages': _readerReverseTapToTurnPages,
      'readerEnableDoubleTapZoom': _readerEnableDoubleTapZoom,
      'readerEnablePageAnimation': _readerEnablePageAnimation,
      'readerAutoPageIntervalSeconds': _readerAutoPageIntervalSeconds,
      'readerPageMode': _readerPageMode.name,
      'readerVerticalMarginPercent': _readerVerticalMarginPercent,
      'readerEnableVolumeKeys': _readerEnableVolumeKeys,
      'readerHorizontalContinuous': _readerHorizontalContinuous,
      'readerShowChapterEdgeButtons': _readerShowChapterEdgeButtons,
      'comicDisplayMode': _comicDisplayMode.name,
      'searchHistoryLimit': _searchHistoryLimit,
      'downloadSaveCover': _downloadSaveCover,
      'language': _language.name,
      'themePreset': _themePreset.name,
      'downloadDirectoryPath': _downloadDirectoryPath,
      'readerCacheDirectoryPath': _readerCacheDirectoryPath,
      'readerCacheLimitMb': _readerCacheLimitMb,
      'webDavUrl': _webDavUrl,
      'webDavUsername': _webDavUsername,
      'webDavPassword': _webDavPassword,
      'webDavAutoSync': _webDavAutoSync,
      'proxyMode': _proxyMode.name,
      'proxyUrl': _sanitizeStoredProxyUrl(_proxyUrl),
      'einkMode': _einkMode,
      'einkHighContrast': _einkHighContrast,
      'einkFullRefreshHint': _einkFullRefreshHint,
      'dataVersion': _dataVersion,
    };
  }

  Future<void> restoreFromBackupJson(Map<String, dynamic> json) async {
    _themeMode = _parseThemeMode(json['themeMode']?.toString());
    _loadSourceIndexSettings(json);
    _readerShowTapGuide = json['readerShowTapGuide'] != false;
    _readerPrefetchCount = _parsePrefetchCount(
      (json['readerPrefetchCount'] as num?)?.toInt(),
    );
    _readerEnableTapToTurnPages = json['readerEnableTapToTurnPages'] != false;
    _readerReverseTapToTurnPages = json['readerReverseTapToTurnPages'] == true;
    _readerEnableDoubleTapZoom = json['readerEnableDoubleTapZoom'] != false;
    _readerEnablePageAnimation = json['readerEnablePageAnimation'] != false;
    _readerAutoPageIntervalSeconds = _parseAutoPageIntervalSeconds(
      (json['readerAutoPageIntervalSeconds'] as num?)?.toDouble(),
    );
    _readerPageMode = _parseReaderPageMode(json['readerPageMode']?.toString());
    _readerVerticalMarginPercent = _parseReaderVerticalMarginPercent(
      (json['readerVerticalMarginPercent'] as num?)?.toDouble(),
    );
    _readerEnableVolumeKeys = json['readerEnableVolumeKeys'] != false;
    _readerHorizontalContinuous = json['readerHorizontalContinuous'] == true;
    _readerShowChapterEdgeButtons =
        json['readerShowChapterEdgeButtons'] != false;
    _comicDisplayMode = _parseComicDisplayMode(
      json['comicDisplayMode']?.toString(),
    );
    _searchHistoryLimit = _parseSearchHistoryLimit(
      (json['searchHistoryLimit'] as num?)?.toInt(),
    );
    _downloadSaveCover = json['downloadSaveCover'] != false;
    _language = _parseLanguage(json['language']?.toString());
    _themePreset = _parseThemePreset(json['themePreset']?.toString());
    _downloadDirectoryPath = _normalizeDirectoryPath(
      json['downloadDirectoryPath']?.toString(),
    );
    _readerCacheDirectoryPath = _normalizeDirectoryPath(
      json['readerCacheDirectoryPath']?.toString(),
    );
    _readerCacheLimitMb = _parseCacheLimitMb(
      (json['readerCacheLimitMb'] as num?)?.toInt(),
    );
    _webDavUrl = json['webDavUrl']?.toString() ?? '';
    _webDavUsername = json['webDavUsername']?.toString() ?? '';
    _webDavPassword = json['webDavPassword']?.toString() ?? '';
    _webDavAutoSync = json['webDavAutoSync'] == true;
    _proxyMode = _parseProxyMode(json['proxyMode']?.toString());
    _proxyUrl = _sanitizeStoredProxyUrl(json['proxyUrl']?.toString() ?? '');
    _einkMode = json['einkMode'] == true;
    _einkHighContrast = json['einkHighContrast'] != false;
    _einkFullRefreshHint = json['einkFullRefreshHint'] != false;
    _dataVersion = (json['dataVersion'] as num?)?.toInt() ?? _dataVersion;
    if (_dataVersion < 0) {
      _dataVersion = 0;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> reset() async {
    _themeMode = ThemeMode.system;
    _sourceIndexUrls = List<String>.of(defaultSourceIndexUrls);
    _sourceIndexUrl = defaultSourceIndexUrl;
    _readerShowTapGuide = true;
    _readerPrefetchCount = 3;
    _readerEnableTapToTurnPages = true;
    _readerReverseTapToTurnPages = false;
    _readerEnableDoubleTapZoom = true;
    _readerEnablePageAnimation = true;
    _readerAutoPageIntervalSeconds = 5;
    _readerPageMode = ReaderPageMode.galleryLeftToRight;
    _readerVerticalMarginPercent = 0;
    _readerEnableVolumeKeys = true;
    _readerHorizontalContinuous = false;
    _readerShowChapterEdgeButtons = true;
    _comicDisplayMode = ComicDisplayMode.grid;
    _searchHistoryLimit = 30;
    _downloadSaveCover = true;
    _language = AppLanguageOption.system;
    _themePreset = AppThemePreset.teal;
    _downloadDirectoryPath = null;
    _readerCacheDirectoryPath = null;
    _webDavUrl = '';
    _webDavUsername = '';
    _webDavPassword = '';
    _webDavAutoSync = false;
    _proxyMode = ProxyMode.system;
    _proxyUrl = '';
    _einkMode = false;
    _einkHighContrast = true;
    _einkFullRefreshHint = true;
    _dataVersion = 0;
    _readerCacheLimitMb = 512;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    // Atomic write via temp file + rename (REQ-011). toBackupJson already
    // strips proxy credentials (ADR-NW-2), so disk never sees them.
    await _store?.write(toBackupJson());
  }

  ThemeMode _parseThemeMode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void _loadSourceIndexSettings(Map<String, dynamic> json) {
    final selected = json['sourceIndexUrl']?.toString().trim();
    final storedList = json['sourceIndexUrls'];
    final urls = <String>[];

    void add(String? value) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty && !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    if (storedList is List) {
      for (final value in storedList) {
        add(value?.toString());
      }
    } else {
      for (final value in defaultSourceIndexUrls) {
        add(value);
      }
    }
    add(selected);
    if (urls.isEmpty) {
      urls.addAll(defaultSourceIndexUrls);
    }

    _sourceIndexUrls = urls;
    _sourceIndexUrl = selected != null && urls.contains(selected)
        ? selected
        : urls.first;
  }

  int _parsePrefetchCount(int? value) {
    if (value == null) {
      return 3;
    }
    return value.clamp(1, 6);
  }

  double _parseAutoPageIntervalSeconds(double? value) {
    if (value == null) {
      return 5;
    }
    return value.clamp(1, 15).toDouble();
  }

  double _parseReaderVerticalMarginPercent(double? value) {
    return (value ?? 0).clamp(0, 30).toDouble();
  }

  ReaderPageMode _parseReaderPageMode(String? value) {
    return switch (value) {
      'galleryRightToLeft' => ReaderPageMode.galleryRightToLeft,
      'continuousTopToBottom' => ReaderPageMode.continuousTopToBottom,
      _ => ReaderPageMode.galleryLeftToRight,
    };
  }

  ComicDisplayMode _parseComicDisplayMode(String? value) {
    return switch (value) {
      'list' => ComicDisplayMode.list,
      _ => ComicDisplayMode.grid,
    };
  }

  AppLanguageOption _parseLanguage(String? value) {
    return switch (value) {
      'english' => AppLanguageOption.english,
      'simplifiedChinese' => AppLanguageOption.simplifiedChinese,
      _ => AppLanguageOption.system,
    };
  }

  AppThemePreset _parseThemePreset(String? value) {
    return switch (value) {
      'amber' => AppThemePreset.amber,
      'rose' => AppThemePreset.rose,
      'blue' => AppThemePreset.blue,
      'forest' => AppThemePreset.forest,
      _ => AppThemePreset.teal,
    };
  }

  ProxyMode _parseProxyMode(String? value) {
    return switch (value) {
      'custom' => ProxyMode.custom,
      'off' => ProxyMode.off,
      _ => ProxyMode.system,
    };
  }

  /// Strips credentials from a proxy URL before it touches disk or backups
  /// (ADR-NW-2: proxy credentials never persist).
  static String _sanitizeStoredProxyUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || uri.userInfo.isEmpty) {
      return value.trim();
    }
    return uri.replace(userInfo: '').toString();
  }

  /// Whether [value] is a usable HTTP(S) proxy URL (`http(s)://host[:port]`).
  static bool isValidProxyUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// The proxy endpoint as `host[:port]` for `findProxy`, or null when the
  /// custom URL is absent/invalid.
  static String? customProxyAuthority(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    return '$host:$port';
  }

  int _parseCacheLimitMb(int? value) {
    if (value == null) {
      return 512;
    }
    return value.clamp(128, 4096);
  }

  int _parseSearchHistoryLimit(int? value) {
    if (value == null) {
      return 30;
    }
    return value.clamp(0, 100);
  }

  String? _normalizeDirectoryPath(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
