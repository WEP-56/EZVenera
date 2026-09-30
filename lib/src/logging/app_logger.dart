import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppLogLevel { info, warning, error }

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int maxLogBytes = 2 * 1024 * 1024;
  static const int trimToBytes = 1536 * 1024;

  File? _logFile;
  Future<void>? _initializeFuture;
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> initialize() async {
    if (_logFile != null) {
      return;
    }
    final existing = _initializeFuture;
    if (existing != null) {
      return existing;
    }
    _initializeFuture = _initialize();
    try {
      return await _initializeFuture!;
    } catch (_) {
      _initializeFuture = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(p.join(supportDirectory.path, 'logs'));
    await directory.create(recursive: true);
    _logFile = File(p.join(directory.path, 'app.log'));
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
    await _trimIfNeeded();

    final packageInfo = await PackageInfo.fromPlatform();
    await info(
      'App started: ${packageInfo.appName} '
      '${packageInfo.version}+${packageInfo.buildNumber} '
      'on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
  }

  Future<File> get logFile async {
    await initialize();
    return _logFile!;
  }

  Future<String> read() async {
    await _pendingWrite;
    final file = await logFile;
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  /// Awaits the write queue so nothing logged while shutting down is lost when
  /// the process exits.
  Future<void> flush() => _pendingWrite.catchError((Object _) {});

  Future<void> clear() async {
    final file = await logFile;
    await file.writeAsString('');
    await info('Log cleared.');
  }

  Future<void> exportToPath(String path) async {
    await _pendingWrite;
    final file = await logFile;
    await file.copy(path);
  }

  Future<void> info(String message) {
    return _write(AppLogLevel.info, message);
  }

  Future<void> warning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    return _write(AppLogLevel.warning, message, error, stackTrace);
  }

  Future<void> error(String message, [Object? error, StackTrace? stackTrace]) {
    return _write(AppLogLevel.error, message, error, stackTrace);
  }

  Future<void> _write(
    AppLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      try {
        final file = await logFile;
        final buffer = StringBuffer()
          ..write(DateTime.now().toIso8601String())
          ..write(' [')
          ..write(level.name.toUpperCase())
          ..write('] ')
          ..writeln(_sanitize(message));
        if (error != null) {
          buffer.writeln(_sanitize(error.toString()));
        }
        if (stackTrace != null) {
          buffer.writeln(_sanitize(stackTrace.toString()));
        }
        await file.writeAsString(buffer.toString(), mode: FileMode.append);
        await _trimIfNeeded();
      } catch (_) {
        // Logging must never be able to break the app itself.
      }
    });
    return _pendingWrite;
  }

  Future<void> _trimIfNeeded() async {
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return;
    }
    final length = await file.length();
    if (length <= maxLogBytes) {
      return;
    }
    final bytes = await file.readAsBytes();
    final keep = bytes.length <= trimToBytes
        ? bytes
        : bytes.sublist(bytes.length - trimToBytes);
    await file.writeAsBytes(keep, flush: true);
  }

  String _sanitize(String value) {
    var result = value;
    final patterns = <RegExp>[
      RegExp(
        r'(password|passwd|pwd|token|cookie|authorization)(\s*[:=]\s*)([^\s,;]+)',
        caseSensitive: false,
      ),
      RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      result = result.replaceAllMapped(pattern, (match) {
        if (match.groupCount >= 3) {
          return '${match.group(1)}${match.group(2)}<redacted>';
        }
        return '${match.group(1)}<redacted>';
      });
    }
    return result;
  }
}
