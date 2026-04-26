import 'dart:async';
import 'dart:io';

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

      final source = await _runtime.installFromString(
        response.data!,
        fileName,
        url,
      );
      _initialized = true;
      return source;
    });
  }

  Future<PluginSource> installFromLocalFile(String filePath) async {
    return _runBusy(() async {
      final file = File(filePath);
      if (!await file.exists()) {
        throw StateError('Plugin file not found.');
      }

      final javascript = await file.readAsString();
      final fileName = file.uri.pathSegments.isEmpty
          ? 'source.js'
          : file.uri.pathSegments.last;

      final source = await _runtime.installFromString(
        javascript,
        fileName.isEmpty ? 'source.js' : fileName,
        null,
      );
      _initialized = true;
      return source;
    });
  }

  Future<void> removeSource(PluginSource source) async {
    await _runBusy(() async {
      await _runtime.removeSource(source);
    });
  }

  Future<void> updateSource(PluginSource source) async {
    final updateUrl = source.updateUrl;
    if (updateUrl.isEmpty) {
      throw StateError('This source does not define an update URL.');
    }

    await _runBusy(() async {
      final response = await _dio.get<String>(updateUrl);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data == null) {
        throw StateError(
          'Failed to update plugin: HTTP ${response.statusCode}',
        );
      }

      final file = File(source.filePath);
      await file.writeAsString(response.data!);
      await _runtime.reload();
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
