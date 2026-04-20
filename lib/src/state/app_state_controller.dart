import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStateController extends ChangeNotifier {
  AppStateController._();

  static final AppStateController instance = AppStateController._();

  bool _initialized = false;
  File? _file;
  Map<String, dynamic> _state = <String, dynamic>{};

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'app_state'));
    await root.create(recursive: true);
    _file = File(p.join(root.path, 'page_state.json'));

    if (await _file!.exists()) {
      try {
        final content = await _file!.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _state = decoded;
        }
      } catch (_) {
        _state = <String, dynamic>{};
        await _persist();
      }
    } else {
      await _persist();
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
    await _file?.writeAsString(jsonEncode(_state));
  }
}
