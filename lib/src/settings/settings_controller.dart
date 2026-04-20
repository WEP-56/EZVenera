import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  static const defaultSourceIndexUrl =
      'https://raw.githubusercontent.com/WEP-56/EZvenera-config/main/index.json';

  bool _initialized = false;
  ThemeMode _themeMode = ThemeMode.system;
  String _sourceIndexUrl = defaultSourceIndexUrl;
  File? _file;

  ThemeMode get themeMode => _themeMode;
  String get sourceIndexUrl => _sourceIndexUrl;
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

  Future<void> reset() async {
    _themeMode = ThemeMode.system;
    _sourceIndexUrl = defaultSourceIndexUrl;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _file?.writeAsString(
      jsonEncode(<String, dynamic>{
        'themeMode': _themeMode.name,
        'sourceIndexUrl': _sourceIndexUrl,
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
}
