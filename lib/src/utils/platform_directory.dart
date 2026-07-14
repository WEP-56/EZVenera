import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class PlatformDirectory {
  const PlatformDirectory._();

  static const MethodChannel _channel = MethodChannel('ezvenera/directory');

  static Future<String?> pickDirectory() async {
    if (Platform.isAndroid) {
      final canUseExternalStorage =
          await _channel.invokeMethod<bool>('ensureStorageAccess') ?? false;
      if (!canUseExternalStorage) {
        throw PlatformException(
          code: 'storage_permission_required',
          message:
              'Storage permission is required before choosing a shared folder.',
        );
      }
      try {
        final path = await _channel.invokeMethod<String>('pickDirectory');
        if (path == null || path.trim().isEmpty) {
          return null;
        }
        return path;
      } on PlatformException catch (error) {
        if (error.code == 'unsupported_directory') {
          throw PlatformException(
            code: error.code,
            message:
                'Please choose a folder under internal shared storage '
                '(for example Download).',
            details: error.details,
          );
        }
        rethrow;
      }
    }
    return getDirectoryPath();
  }

  /// Pick a destination path for writing a file.
  ///
  /// Desktop platforms use the native save dialog via [getSaveLocation].
  /// Android does not implement that API in `file_selector`, so we fall back
  /// to the existing shared-storage directory picker and join [suggestedName].
  static Future<String?> pickSavePath({
    required String suggestedName,
    List<XTypeGroup> acceptedTypeGroups = const <XTypeGroup>[],
  }) async {
    final fileName = suggestedName.trim().isEmpty
        ? 'export.bin'
        : p.basename(suggestedName.trim());
    if (Platform.isAndroid) {
      final directory = await pickDirectory();
      if (directory == null || directory.trim().isEmpty) {
        return null;
      }
      return p.join(directory, fileName);
    }

    final location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      suggestedName: fileName,
    );
    return location?.path;
  }

  static Future<bool> openDirectory(String path) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path]);
      return true;
    }
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('openDirectory', path) ?? false;
    }
    return launchUrl(Uri.directory(path), mode: LaunchMode.externalApplication);
  }
}
