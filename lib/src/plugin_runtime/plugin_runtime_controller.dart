import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'plugin_runtime.dart';

class PluginRuntimeController extends ChangeNotifier {
  PluginRuntimeController._();

  static final PluginRuntimeController instance = PluginRuntimeController._();

  final PluginRuntime _runtime = PluginRuntime.instance;
  final Dio _dio = Dio(
    BaseOptions(responseType: ResponseType.plain, validateStatus: (_) => true),
  );

  bool _initialized = false;
  bool _busy = false;
  String? _errorMessage;

  bool get isInitialized => _initialized;
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  List<PluginSource> get sources => _runtime.sources;

  PluginSource? find(String key) => _runtime.find(key);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _runBusy(() async {
      await _runtime.ensureInitialized();
      _initialized = true;
    });
  }

  Future<void> reload() async {
    await _runBusy(() async {
      await _runtime.reload();
      _initialized = true;
    });
  }

  Future<PluginSource> installFromUrl(String url) async {
    return _runBusy(() async {
      final response = await _dio.get<String>(url);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data == null) {
        throw StateError(
          'Failed to download plugin: HTTP ${response.statusCode}',
        );
      }

      final uri = Uri.parse(url);
      var fileName = uri.pathSegments.isEmpty
          ? 'source.js'
          : uri.pathSegments.last;
      if (fileName.isEmpty) {
        fileName = 'source.js';
      }

      final source = await _runtime.installFromString(response.data!, fileName);
      _initialized = true;
      return source;
    });
  }

  Future<void> removeSource(PluginSource source) async {
    await _runBusy(() async {
      await _runtime.removeSource(source);
    });
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await action();
      return result;
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
