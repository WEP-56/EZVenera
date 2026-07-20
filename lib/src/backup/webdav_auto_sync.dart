import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/favorite_controller.dart';
import '../library/history_controller.dart';
import '../logging/app_logger.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../settings/settings_controller.dart';
import 'backup_service.dart';

/// WebDAV auto-sync, adapted from upstream Venera's `DataSync`.
///
/// Behaviour:
/// - When enabled + configured: download newer remote backup on startup.
/// - On local data changes (favorites / history / sources): debounced upload.
/// - Uses `dataVersion` so a device with newer local data is not clobbered.
class WebDavAutoSync extends ChangeNotifier {
  WebDavAutoSync._();

  static final WebDavAutoSync instance = WebDavAutoSync._();

  static const Duration _uploadDebounce = Duration(seconds: 3);

  bool _started = false;
  bool _isDownloading = false;
  bool _isUploading = false;
  bool _haveWaitingTask = false;
  String? _lastError;
  Timer? _uploadDebounceTimer;

  bool get isDownloading => _isDownloading;
  bool get isUploading => _isUploading;
  String? get lastError => _lastError;

  bool get isEnabled {
    final settings = SettingsController.instance;
    return settings.webDavAutoSync && settings.hasWebDavConfig;
  }

  /// Wire listeners and run the startup download when auto-sync is on.
  /// Call once after app controllers have finished initializing.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    FavoriteController.instance.addListener(_onDataChanged);
    HistoryController.instance.addListener(_onDataChanged);
    PluginRuntimeController.instance.addListener(_onDataChanged);

    if (isEnabled) {
      unawaited(downloadData());
    }
  }

  void _onDataChanged() {
    if (!isEnabled) {
      return;
    }
    _uploadDebounceTimer?.cancel();
    _uploadDebounceTimer = Timer(_uploadDebounce, () {
      unawaited(uploadData());
    });
  }

  /// Manual / auto upload entry (safe to call when disabled — no-ops config).
  Future<bool> uploadData() async {
    if (_isDownloading) {
      return true;
    }
    if (_haveWaitingTask) {
      return true;
    }
    while (_isUploading) {
      _haveWaitingTask = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;

    final settings = SettingsController.instance;
    if (!settings.hasWebDavConfig) {
      return true;
    }

    _isUploading = true;
    _lastError = null;
    notifyListeners();

    try {
      final dataVersion = await settings.incrementDataVersion();
      await BackupService.instance.uploadVersionedToWebDav(
        url: settings.webDavUrl,
        username: settings.webDavUsername,
        password: settings.webDavPassword,
        dataVersion: dataVersion,
      );
      unawaited(AppLogger.instance.info('WebDAV auto-sync: upload ok (v$dataVersion)'));
      return true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      unawaited(
        AppLogger.instance.error('WebDAV auto-sync upload failed', error, stackTrace),
      );
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Startup / toggle-on download. Skips when remote dataVersion is not newer.
  Future<bool> downloadData() async {
    if (_haveWaitingTask) {
      return true;
    }
    while (_isDownloading || _isUploading) {
      _haveWaitingTask = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;

    final settings = SettingsController.instance;
    if (!settings.hasWebDavConfig) {
      return true;
    }

    _isDownloading = true;
    _lastError = null;
    notifyListeners();

    try {
      final report = await BackupService.instance.downloadNewerFromWebDav(
        url: settings.webDavUrl,
        username: settings.webDavUsername,
        password: settings.webDavPassword,
        localDataVersion: settings.dataVersion,
      );
      if (report == null) {
        unawaited(
          AppLogger.instance.info('WebDAV auto-sync: no newer remote backup'),
        );
      } else {
        unawaited(
          AppLogger.instance.info(
            'WebDAV auto-sync: downloaded remote backup '
            '(sources=${report.sources}, favorites=${report.favorites}, '
            'history=${report.history})',
          ),
        );
      }
      return true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      unawaited(
        AppLogger.instance.error(
          'WebDAV auto-sync download failed',
          error,
          stackTrace,
        ),
      );
      return false;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }
}
