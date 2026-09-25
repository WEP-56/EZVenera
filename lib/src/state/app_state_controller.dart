import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/json_file_store.dart';

class AppStateController extends ChangeNotifier {
  AppStateController._();

  static final AppStateController instance = AppStateController._();

  bool _initialized = false;
  JsonFileStore? _store;
  Map<String, dynamic> _state = <String, dynamic>{};

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'app_state'));
    await root.create(recursive: true);
    _store = JsonFileStore(File(p.join(root.path, 'page_state.json')));

    // Missing or corrupted files yield an empty map; rewrite a healthy file
    // so corruption self-heals on next launch (REQ-011).
    final decoded = await _store!.read();
    if (decoded.isEmpty) {
      await _persist();
    } else {
      _state = decoded;
    }

    _initialized = true;
    notifyListeners();
  }

  int? getInt(String key) {
    final value = _state[key];
    return value is num ? value.toInt() : null;
  }

  String? getString(String key) => _state[key]?.toString();

  Map<String, dynamic> getSection(String key) {
    final value = _state[key];
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> toBackupJson() {
    return Map<String, dynamic>.from(_state);
  }

  Future<void> restoreFromBackupJson(Map<String, dynamic> value) async {
    _state = Map<String, dynamic>.from(value);
    await _persist();
    notifyListeners();
  }

  Future<void> setInt(String key, int value) async {
    _state[key] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setString(String key, String value) async {
    _state[key] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setSection(String key, Map<String, dynamic> value) async {
    _state[key] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store?.write(_state);
  }
}
