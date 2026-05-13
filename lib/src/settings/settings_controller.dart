import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../localization/app_localizations.dart';

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
enum ReaderPageMode { galleryLeftToRight, galleryRightToLeft, continuousTopToBottom }

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  static const defaultSourceIndexUrl =
      'https://raw.githubusercontent.com/WEP-56/EZvenera-config/main/index.json';

  bool _initialized = false;
  ThemeMode _themeMode = ThemeMode.system;
  String _sourceIndexUrl = defaultSourceIndexUrl;
  bool _readerShowTapGuide = true;
  int _readerPrefetchCount = 3;
  bool _readerEnableTapToTurnPages = true;
  bool _readerReverseTapToTurnPages = false;
  bool _readerEnableDoubleTapZoom = true;
  bool _readerEnablePageAnimation = true;
  double _readerAutoPageIntervalSeconds = 5;
  ReaderPageMode _readerPageMode = ReaderPageMode.galleryLeftToRight;
  bool _readerEnableVolumeKeys = true;
  bool _readerHorizontalContinuous = false;
  ComicDisplayMode _comicDisplayMode = ComicDisplayMode.grid;
  bool _downloadSaveCover = true;
  AppLanguageOption _language = AppLanguageOption.system;
  AppThemePreset _themePreset = AppThemePreset.teal;
  String? _downloadDirectoryPath;
  String? _readerCacheDirectoryPath;
  int _readerCacheLimitMb = 512;
  File? _file;

  ThemeMode get themeMode => _themeMode;
  String get sourceIndexUrl => _sourceIndexUrl;
  bool get readerShowTapGuide => _readerShowTapGuide;
  int get readerPrefetchCount => _readerPrefetchCount;
  bool get readerEnableTapToTurnPages => _readerEnableTapToTurnPages;
  bool get readerReverseTapToTurnPages => _readerReverseTapToTurnPages;
  bool get readerEnableDoubleTapZoom => _readerEnableDoubleTapZoom;
  bool get readerEnablePageAnimation => _readerEnablePageAnimation;
  double get readerAutoPageIntervalSeconds => _readerAutoPageIntervalSeconds;
  ReaderPageMode get readerPageMode => _readerPageMode;
  bool get readerEnableVolumeKeys => _readerEnableVolumeKeys;
  bool get readerHorizontalContinuous => _readerHorizontalContinuous;
  ComicDisplayMode get comicDisplayMode => _comicDisplayMode;
  bool get downloadSaveCover => _downloadSaveCover;
  AppLanguageOption get language => _language;
  AppThemePreset get themePreset => _themePreset;
  String? get downloadDirectoryPath => _downloadDirectoryPath;
  String? get readerCacheDirectoryPath => _readerCacheDirectoryPath;
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

    if (await _file!.exists()) {
      final content = await _file!.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _themeMode = _parseThemeMode(decoded['themeMode']?.toString());
        _sourceIndexUrl =
            decoded['sourceIndexUrl']?.toString() ?? defaultSourceIndexUrl;
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
        _readerEnableVolumeKeys =
            decoded['readerEnableVolumeKeys'] != false;
        _readerHorizontalContinuous =
            decoded['readerHorizontalContinuous'] == true;
        _comicDisplayMode = _parseComicDisplayMode(
          decoded['comicDisplayMode']?.toString(),
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
        _readerCacheLimitMb = _parseCacheLimitMb(
          (decoded['readerCacheLimitMb'] as num?)?.toInt(),
        );
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
    _sourceIndexUrl = normalized;
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

  Future<void> setComicDisplayMode(ComicDisplayMode value) async {
    if (_comicDisplayMode == value) {
      return;
    }
    _comicDisplayMode = value;
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

  Future<void> reset() async {
    _themeMode = ThemeMode.system;
    _sourceIndexUrl = defaultSourceIndexUrl;
    _readerShowTapGuide = true;
    _readerPrefetchCount = 3;
    _readerEnableTapToTurnPages = true;
    _readerReverseTapToTurnPages = false;
    _readerEnableDoubleTapZoom = true;
    _readerEnablePageAnimation = true;
    _readerAutoPageIntervalSeconds = 5;
    _readerPageMode = ReaderPageMode.galleryLeftToRight;
    _readerEnableVolumeKeys = true;
    _readerHorizontalContinuous = false;
    _comicDisplayMode = ComicDisplayMode.grid;
    _downloadSaveCover = true;
    _language = AppLanguageOption.system;
    _themePreset = AppThemePreset.teal;
    _downloadDirectoryPath = null;
    _readerCacheDirectoryPath = null;
    _readerCacheLimitMb = 512;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _file?.writeAsString(
      jsonEncode(<String, dynamic>{
        'themeMode': _themeMode.name,
        'sourceIndexUrl': _sourceIndexUrl,
        'readerShowTapGuide': _readerShowTapGuide,
        'readerPrefetchCount': _readerPrefetchCount,
        'readerEnableTapToTurnPages': _readerEnableTapToTurnPages,
        'readerReverseTapToTurnPages': _readerReverseTapToTurnPages,
        'readerEnableDoubleTapZoom': _readerEnableDoubleTapZoom,
        'readerEnablePageAnimation': _readerEnablePageAnimation,
        'readerAutoPageIntervalSeconds': _readerAutoPageIntervalSeconds,
        'readerPageMode': _readerPageMode.name,
        'readerEnableVolumeKeys': _readerEnableVolumeKeys,
        'readerHorizontalContinuous': _readerHorizontalContinuous,
        'comicDisplayMode': _comicDisplayMode.name,
        'downloadSaveCover': _downloadSaveCover,
        'language': _language.name,
        'themePreset': _themePreset.name,
        'downloadDirectoryPath': _downloadDirectoryPath,
        'readerCacheDirectoryPath': _readerCacheDirectoryPath,
        'readerCacheLimitMb': _readerCacheLimitMb,
      }),
    );
  }

  ThemeMode _parseThemeMode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
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

  int _parseCacheLimitMb(int? value) {
    if (value == null) {
      return 512;
    }
    return value.clamp(128, 4096);
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
