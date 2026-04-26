import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'engine/plugin_js_engine.dart';
import 'models.dart';
import 'parser/plugin_source_parser.dart';
import 'repository/plugin_source_repository.dart';
import 'storage/cookie_store.dart';
import 'storage/plugin_data_store.dart';

class PluginRuntime {
  PluginRuntime._();

  static final PluginRuntime instance = PluginRuntime._();

  late PluginCookieStore cookieStore;
  late PluginDataStore dataStore;
  late PluginJsEngine engine;
  late PluginSourceParser parser;
  late PluginSourceRepository repository;

  final List<PluginSource> _sources = [];
  bool _initialized = false;

  List<PluginSource> get sources => List<PluginSource>.unmodifiable(_sources);

  PluginSource? find(String key) {
    for (final source in _sources) {
      if (source.key == key) {
        return source;
      }
    }
    return null;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version.trim().isEmpty
        ? '0.1.0'
        : packageInfo.version.trim();

    final supportDir = await getApplicationSupportDirectory();
    final runtimeRoot = Directory(p.join(supportDir.path, 'plugin_runtime'));
    await runtimeRoot.create(recursive: true);

    cookieStore = PluginCookieStore(p.join(runtimeRoot.path, 'cookies.db'));
    cookieStore.initialize();
    dataStore = PluginDataStore(p.join(runtimeRoot.path, 'data'));
    engine = PluginJsEngine(
      dataStore: dataStore,
      cookieStore: cookieStore,
      appVersion: appVersion,
    );
    parser = PluginSourceParser(
      engine: engine,
      dataStore: dataStore,
      appVersion: appVersion,
    );
    repository = PluginSourceRepository(
      sourcesPath: p.join(runtimeRoot.path, 'sources'),
      dataStore: dataStore,
      parser: parser,
    );

    await reload();

    _initialized = true;
  }

  Future<void> reload() async {
    engine.resetSources();
    _sources
      ..clear()
      ..addAll(await repository.loadAll());
  }

  Future<PluginSource> installFromString(
    String javascript,
    String fileName,
    String? installSourceUrl,
  ) async {
    final source = await repository.installFromString(
      javascript,
      fileName,
      installSourceUrl: installSourceUrl,
    );
    _sources.add(source);
    return source;
  }

  Future<void> removeSource(PluginSource source) async {
    await repository.removeSource(source);
    _sources.removeWhere((item) => item.key == source.key);
    await reload();
  }
}
