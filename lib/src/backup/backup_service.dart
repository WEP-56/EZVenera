import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../library/favorite_controller.dart';
import '../library/favorite_models.dart';
import '../library/history_controller.dart';
import '../library/history_models.dart';
import '../plugin_runtime/plugin_runtime.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../settings/settings_controller.dart';
import '../state/app_state_controller.dart';

class BackupImportReport {
  const BackupImportReport({
    this.sources = 0,
    this.favorites = 0,
    this.history = 0,
    this.cookies = 0,
  });

  final int sources;
  final int favorites;
  final int history;
  final int cookies;
}

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  final Dio _dio = Dio(BaseOptions(validateStatus: (_) => true));

  Future<File> exportToTemporaryFile() async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, _backupFileName()));
    await exportToPath(file.path);
    return file;
  }

  Future<void> exportToPath(String path) async {
    await PluginRuntime.instance.ensureInitialized();
    await FavoriteController.instance.initialize();
    await HistoryController.instance.initialize();
    await SettingsController.instance.initialize();
    await AppStateController.instance.initialize();

    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(<String, dynamic>{
          'format': 'ezvenera.backup',
          'version': 1,
          'createdAt': DateTime.now().toIso8601String(),
        }),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'library/favorites.json',
        jsonEncode(
          FavoriteController.instance.entries
              .map((entry) => entry.toJson())
              .toList(),
        ),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'library/history.json',
        jsonEncode(
          HistoryController.instance.entries
              .map((entry) => entry.toJson())
              .toList(),
        ),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'settings/app_settings.json',
        jsonEncode(SettingsController.instance.toBackupJson()),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'app_state/page_state.json',
        jsonEncode(AppStateController.instance.toBackupJson()),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'plugin_runtime/cookies.json',
        jsonEncode(PluginRuntime.instance.cookieStore.exportRows()),
      ),
    );

    await _addDirectory(
      archive,
      Directory(PluginRuntime.instance.repository.sourcesPath),
      'plugin_runtime/sources',
    );
    await _addDirectory(
      archive,
      Directory(PluginRuntime.instance.dataStore.rootPath),
      'plugin_runtime/data',
    );

    final bytes = ZipEncoder().encode(archive);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<BackupImportReport> importFromPath(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (_entry(archive, 'manifest.json') != null) {
      return _importEzVeneraBackup(archive);
    }
    return _importVeneraBackup(archive);
  }

  Future<File> uploadToWebDav({
    required String url,
    required String username,
    required String password,
  }) async {
    final file = await exportToTemporaryFile();
    final client = _WebDavClient(
      dio: _dio,
      url: url,
      username: username,
      password: password,
    );
    await client.upload(file);
    return file;
  }

  Future<BackupImportReport> downloadLatestFromWebDav({
    required String url,
    required String username,
    required String password,
  }) async {
    final client = _WebDavClient(
      dio: _dio,
      url: url,
      username: username,
      password: password,
    );
    final file = await client.downloadLatest();
    return importEzVeneraFromPath(file.path);
  }

  Future<BackupImportReport> importEzVeneraFromPath(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = _jsonMap(_readString(archive, 'manifest.json'));
    if (manifest['format'] != 'ezvenera.backup') {
      throw StateError('The selected WebDAV backup is not an EZVenera backup.');
    }
    return _importEzVeneraBackup(archive);
  }

  Future<BackupImportReport> _importEzVeneraBackup(Archive archive) async {
    await PluginRuntime.instance.ensureInitialized();

    final favorites = _jsonList(
      _readString(archive, 'library/favorites.json'),
    ).map(LocalFavoriteEntry.fromJson).toList();
    final history = _jsonList(
      _readString(archive, 'library/history.json'),
    ).map(ReadingHistoryEntry.fromJson).toList();
    final settings = _jsonMap(
      _readString(archive, 'settings/app_settings.json'),
    );
    final appState = _jsonMap(
      _readString(archive, 'app_state/page_state.json'),
    );
    final cookies = _jsonList(
      _readString(archive, 'plugin_runtime/cookies.json'),
    );

    await _restoreDirectory(
      archive,
      'plugin_runtime/sources/',
      PluginRuntime.instance.repository.sourcesPath,
    );
    await _restoreDirectory(
      archive,
      'plugin_runtime/data/',
      PluginRuntime.instance.dataStore.rootPath,
    );

    await FavoriteController.instance.replaceEntries(favorites);
    await HistoryController.instance.replaceEntries(history);
    if (settings.isNotEmpty) {
      await SettingsController.instance.restoreFromBackupJson(settings);
    }
    if (appState.isNotEmpty) {
      await AppStateController.instance.restoreFromBackupJson(appState);
    }
    PluginRuntime.instance.cookieStore.replaceRows(cookies);
    await PluginRuntimeController.instance.reload();

    return BackupImportReport(
      sources: PluginRuntimeController.instance.sources.length,
      favorites: favorites.length,
      history: history.length,
      cookies: cookies.length,
    );
  }

  Future<BackupImportReport> _importVeneraBackup(Archive archive) async {
    await PluginRuntime.instance.ensureInitialized();

    final sourceCount = await _importVeneraSources(archive);
    final dataCount = await _importVeneraSourceData(archive);
    await PluginRuntimeController.instance.reload();

    final sourceKeys = _sourceKeyByType();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'ezvenera_import_',
    );
    try {
      final favoritesDb = await _writeEntryToTemp(
        archive,
        'local_favorite.db',
        tempDirectory,
      );
      final historyDb = await _writeEntryToTemp(
        archive,
        'history.db',
        tempDirectory,
      );
      final cookieDb = await _writeEntryToTemp(
        archive,
        'cookie.db',
        tempDirectory,
      );

      final favorites = favoritesDb == null
          ? <LocalFavoriteEntry>[]
          : _readVeneraFavorites(favoritesDb, sourceKeys);
      final history = historyDb == null
          ? <ReadingHistoryEntry>[]
          : _readVeneraHistory(historyDb, sourceKeys);
      final cookies = cookieDb == null
          ? <Map<String, dynamic>>[]
          : _readVeneraCookies(cookieDb);

      await FavoriteController.instance.mergeEntries(favorites);
      await HistoryController.instance.mergeEntries(history);
      PluginRuntime.instance.cookieStore.mergeRows(cookies);
      await PluginRuntimeController.instance.reload();

      return BackupImportReport(
        sources: sourceCount + dataCount,
        favorites: favorites.length,
        history: history.length,
        cookies: cookies.length,
      );
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<int> _importVeneraSources(Archive archive) async {
    var count = 0;
    final sourceDir = Directory(PluginRuntime.instance.repository.sourcesPath);
    await sourceDir.create(recursive: true);

    for (final file in archive.files) {
      final name = _normalizeArchiveName(file.name);
      if (!file.isFile ||
          !name.startsWith('comic_source/') ||
          !name.endsWith('.js')) {
        continue;
      }
      final javascript = utf8.decode(file.content);
      final sourceKey = _extractSourceKey(javascript);
      final existing = sourceKey == null
          ? null
          : PluginRuntimeController.instance.find(sourceKey);
      final target = existing == null
          ? await _availableFile(sourceDir.path, p.basename(name))
          : File(existing.filePath);
      await target.parent.create(recursive: true);
      await target.writeAsString(javascript, flush: true);
      count++;
    }
    return count;
  }

  Future<int> _importVeneraSourceData(Archive archive) async {
    var count = 0;
    await PluginRuntime.instance.dataStore.ensureInitialized();
    for (final file in archive.files) {
      final name = _normalizeArchiveName(file.name);
      if (!file.isFile ||
          !name.startsWith('comic_source/') ||
          !name.endsWith('.data')) {
        continue;
      }
      final key = p.basenameWithoutExtension(name);
      final decoded = jsonDecode(utf8.decode(file.content));
      if (decoded is! Map) {
        continue;
      }
      await PluginRuntime.instance.dataStore.write(
        key,
        Map<String, dynamic>.from(decoded),
      );
      count++;
    }
    return count;
  }

  List<LocalFavoriteEntry> _readVeneraFavorites(
    File dbFile,
    Map<int, String> sourceKeys,
  ) {
    final db = sqlite3.open(dbFile.path);
    try {
      final result = <LocalFavoriteEntry>[];
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((row) => row['name'] as String)
          .where((name) => name != 'folder_order' && name != 'folder_sync');
      for (final table in tables) {
        final rows = db.select('SELECT * FROM ${_quoteIdentifier(table)};');
        for (final row in rows) {
          final sourceKey = _sourceKeyFromType(row['type'], sourceKeys);
          final comicId = row['id']?.toString();
          final title = row['name']?.toString();
          if (sourceKey == null || comicId == null || title == null) {
            continue;
          }
          result.add(
            LocalFavoriteEntry(
              sourceKey: sourceKey,
              comicId: comicId,
              title: title,
              subtitle: row['author']?.toString(),
              cover: row['cover_path']?.toString(),
              description: table,
              tags: _splitTags(row['tags']?.toString()),
              createdAt: _parseVeneraFavoriteTime(row['time']?.toString()),
            ),
          );
        }
      }
      return result;
    } finally {
      db.dispose();
    }
  }

  List<ReadingHistoryEntry> _readVeneraHistory(
    File dbFile,
    Map<int, String> sourceKeys,
  ) {
    final db = sqlite3.open(dbFile.path);
    try {
      final result = <ReadingHistoryEntry>[];
      final rows = db.select('SELECT * FROM history;');
      for (final row in rows) {
        final sourceKey = _sourceKeyFromType(row['type'], sourceKeys);
        final comicId = row['id']?.toString();
        final title = row['title']?.toString();
        if (sourceKey == null || comicId == null || title == null) {
          continue;
        }
        final ep = (row['ep'] as num?)?.toInt();
        result.add(
          ReadingHistoryEntry(
            sourceKey: sourceKey,
            comicId: comicId,
            title: title,
            subtitle: row['subtitle']?.toString(),
            cover: row['cover']?.toString(),
            chapterId: ep == null || ep < 1 ? null : ep.toString(),
            chapterTitle: ep == null || ep < 1 ? null : 'Chapter $ep',
            page: ((row['page'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (row['time'] as num?)?.toInt() ?? 0,
            ),
          ),
        );
      }
      return result;
    } finally {
      db.dispose();
    }
  }

  List<Map<String, dynamic>> _readVeneraCookies(File dbFile) {
    final db = sqlite3.open(dbFile.path);
    try {
      return db
          .select(
            'SELECT name, value, domain, path, expires, secure, httpOnly FROM cookies;',
          )
          .map(
            (row) => <String, dynamic>{
              'name': row['name'],
              'value': row['value'],
              'domain': row['domain'],
              'path': row['path'],
              'expires': row['expires'],
              'secure': row['secure'],
              'http_only': row['httpOnly'],
            },
          )
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    } finally {
      db.dispose();
    }
  }

  Map<int, String> _sourceKeyByType() {
    return <int, String>{
      0: 'picacg',
      1: 'ehentai',
      2: 'jm',
      3: 'hitomi',
      4: 'wnacg',
      5: 'nhentai',
      6: 'nhentai',
      for (final source in PluginRuntimeController.instance.sources)
        source.key.hashCode: source.key,
    };
  }

  String? _sourceKeyFromType(Object? type, Map<int, String> sourceKeys) {
    final value = (type as num?)?.toInt();
    if (value == null) {
      return null;
    }
    return sourceKeys[value];
  }

  Future<void> _addDirectory(
    Archive archive,
    Directory directory,
    String archivePrefix,
  ) async {
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: directory.path);
      final name = p.posix.join(archivePrefix, p.split(relative).join('/'));
      archive.addFile(ArchiveFile.bytes(name, await entity.readAsBytes()));
    }
  }

  Future<void> _restoreDirectory(
    Archive archive,
    String archivePrefix,
    String targetPath,
  ) async {
    final directory = Directory(targetPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    for (final file in archive.files) {
      final name = _normalizeArchiveName(file.name);
      if (!file.isFile || !name.startsWith(archivePrefix)) {
        continue;
      }
      final relative = name.substring(archivePrefix.length);
      if (relative.isEmpty || relative.contains('..')) {
        continue;
      }
      final target = File(
        p.joinAll(<String>[targetPath, ...relative.split('/')]),
      );
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content, flush: true);
    }
  }

  Future<File?> _writeEntryToTemp(
    Archive archive,
    String name,
    Directory directory,
  ) async {
    final entry = _entry(archive, name);
    if (entry == null || !entry.isFile) {
      return null;
    }
    final file = File(p.join(directory.path, name));
    await file.writeAsBytes(entry.content, flush: true);
    return file;
  }

  ArchiveFile? _entry(Archive archive, String name) {
    for (final file in archive.files) {
      if (_normalizeArchiveName(file.name) == name) {
        return file;
      }
    }
    return null;
  }

  String? _readString(Archive archive, String name) {
    final entry = _entry(archive, name);
    if (entry == null || !entry.isFile) {
      return null;
    }
    return utf8.decode(entry.content);
  }

  List<Map<String, dynamic>> _jsonList(String? content) {
    if (content == null) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return const <Map<String, dynamic>>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _jsonMap(String? content) {
    if (content == null) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  List<String> _splitTags(String? value) {
    if (value == null || value.isEmpty) {
      return const <String>[];
    }
    return value
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  DateTime _parseVeneraFavoriteTime(String? value) {
    if (value == null || value.isEmpty) {
      return DateTime.now();
    }
    return DateTime.tryParse(value.replaceFirst(' ', 'T')) ?? DateTime.now();
  }

  String? _extractSourceKey(String javascript) {
    final patterns = <RegExp>[
      RegExp(r'''get\s+key\s*\(\)\s*\{\s*return\s*['"]([^'"]+)['"]'''),
      RegExp(r'''key\s*=\s*['"]([^'"]+)['"]'''),
      RegExp(r'''this\.key\s*=\s*['"]([^'"]+)['"]'''),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(javascript);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  Future<File> _availableFile(String directory, String fileName) async {
    final normalized = fileName.endsWith('.js') ? fileName : '$fileName.js';
    var target = File(p.join(directory, normalized));
    var index = 1;
    while (await target.exists()) {
      final base = normalized.substring(0, normalized.length - 3);
      target = File(p.join(directory, '$base($index).js'));
      index++;
    }
    return target;
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  String _normalizeArchiveName(String name) {
    return name.replaceAll('\\', '/');
  }

  String _backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'EZVenera-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.ezvenera';
  }
}

class _WebDavClient {
  _WebDavClient({
    required this.dio,
    required String url,
    required this.username,
    required this.password,
  }) : baseUri = _normalizeUrl(url);

  final Dio dio;
  final Uri baseUri;
  final String username;
  final String password;

  Future<void> upload(File file) async {
    final uri = baseUri.resolve(p.basename(file.path));
    final response = await dio.put<dynamic>(
      uri.toString(),
      data: await file.readAsBytes(),
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, String>{
          ..._headers(),
          'Content-Type': 'application/octet-stream',
        },
      ),
    );
    if (!_isSuccess(response.statusCode)) {
      throw StateError('WebDAV upload failed: HTTP ${response.statusCode}');
    }
  }

  Future<File> downloadLatest() async {
    final files = await listBackups();
    if (files.isEmpty) {
      throw StateError('No .ezvenera backup found on WebDAV.');
    }
    files.sort((a, b) => b.name.compareTo(a.name));
    final backup = files.first;
    final response = await dio.get<List<int>>(
      baseUri.resolve(backup.relativePath).toString(),
      options: Options(responseType: ResponseType.bytes, headers: _headers()),
    );
    if (!_isSuccess(response.statusCode) || response.data == null) {
      throw StateError('WebDAV download failed: HTTP ${response.statusCode}');
    }
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, backup.name));
    await file.writeAsBytes(response.data!, flush: true);
    return file;
  }

  Future<List<_WebDavBackupFile>> listBackups() async {
    final response = await dio.request<String>(
      baseUri.toString(),
      data: '''<?xml version="1.0" encoding="utf-8" ?>
<propfind xmlns="DAV:"><allprop /></propfind>''',
      options: Options(
        method: 'PROPFIND',
        responseType: ResponseType.plain,
        headers: <String, String>{
          ..._headers(),
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
      ),
    );
    if (!_isSuccess(response.statusCode) || response.data == null) {
      throw StateError('WebDAV list failed: HTTP ${response.statusCode}');
    }
    final hrefs = RegExp(
      r'<(?:\w+:)?href>([^<]+)</(?:\w+:)?href>',
      caseSensitive: false,
    ).allMatches(response.data!).map((match) => _xmlDecode(match.group(1)!));
    final result = <String, _WebDavBackupFile>{};
    for (final href in hrefs) {
      final relativePath = _relativePathFromHref(href);
      final name = p.posix.basename(relativePath);
      if (name.endsWith('.ezvenera')) {
        result[name] = _WebDavBackupFile(
          name: name,
          relativePath: relativePath,
        );
      }
    }
    return result.values.toList();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{};
    if (username.isNotEmpty || password.isNotEmpty) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    }
    return headers;
  }

  bool _isSuccess(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  static Uri _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw StateError('WebDAV URL is empty.');
    }
    final normalized = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    final uri = Uri.parse(normalized);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Invalid WebDAV URL.');
    }
    return uri;
  }

  String _relativePathFromHref(String href) {
    final hrefUri = Uri.tryParse(href);
    final hrefSegments = hrefUri?.pathSegments ?? Uri(path: href).pathSegments;
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    var segments = hrefSegments
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList();

    if (segments.length >= baseSegments.length) {
      var matchesBase = true;
      for (var index = 0; index < baseSegments.length; index++) {
        if (Uri.decodeComponent(baseSegments[index]) != segments[index]) {
          matchesBase = false;
          break;
        }
      }
      if (matchesBase) {
        segments = segments.sublist(baseSegments.length);
      }
    }

    return segments.map(Uri.encodeComponent).join('/');
  }

  String _xmlDecode(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}

class _WebDavBackupFile {
  const _WebDavBackupFile({required this.name, required this.relativePath});

  final String name;
  final String relativePath;
}
