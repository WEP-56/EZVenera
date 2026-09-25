import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/services/plugin_image_loader.dart';
import '../settings/settings_controller.dart';
import 'page_height_cache.dart';

class ReaderImageCache {
  ReaderImageCache._();

  static final ReaderImageCache instance = ReaderImageCache._();
  static const _cacheVersion = 'v2';

  static const _maxMemoryEntries = 48;

  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _pending = <String, Future<Uint8List>>{};
  final List<String> _memoryOrder = <String>[];
  Directory? _cacheRoot;

  Future<Uint8List> load({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final cacheKey = _cacheKey(source.key, comicId, episodeId, imageUrl);
    final cached = _memory[cacheKey];
    if (cached != null) {
      _touch(cacheKey);
      return cached;
    }

    final pending = _pending[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _loadInternal(
      cacheKey: cacheKey,
      source: source,
      comicId: comicId,
      episodeId: episodeId,
      imageUrl: imageUrl,
    );
    _pending[cacheKey] = future;
    try {
      return await future;
    } finally {
      _pending.remove(cacheKey);
    }
  }

  /// Bytes already held in memory for this page, or null.
  ///
  /// The reader uses this to warm [PageHeightCache] from pages it has on hand:
  /// a page's height is then exact on the very first layout, instead of being
  /// corrected after the image arrives (which is what made the vertical
  /// continuous list jump and roll back). Never touches the network.
  Uint8List? memoryBytes({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) {
    return _memory[_cacheKey(source.key, comicId, episodeId, imageUrl)];
  }

  void prefetch({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) {
    unawaited(_prefetchInternal(source, comicId, episodeId, imageUrl));
  }

  Future<String> currentRootPath() async {
    _cacheRoot ??= await _resolveRoot();
    return _cacheRoot!.path;
  }

  /// Drops the in-memory and on-disk entry for one image (REQ-009). Called
  /// when cached bytes turn out to be undecodable, so a retry re-downloads
  /// instead of reading the same corrupted file forever.
  Future<void> evict({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final cacheKey = _cacheKey(source.key, comicId, episodeId, imageUrl);
    _memory.remove(cacheKey);
    _memoryOrder.remove(cacheKey);
    try {
      final file = await _fileForKey(cacheKey);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort: a file that cannot be deleted will be overwritten on
      // the next successful download anyway.
    }
  }

  Future<int> diskUsageBytes() async {
    final root = await _resolveRoot();
    if (!await root.exists()) {
      return 0;
    }

    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += (await entity.stat()).size;
      }
    }
    return total;
  }

  Future<void> clearDiskCache() async {
    _memory.clear();
    _memoryOrder.clear();
    final root = await _resolveRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    _cacheRoot = null;
    await _resolveRoot();
  }

  Future<void> reloadConfiguration() async {
    _memory.clear();
    _memoryOrder.clear();
    _cacheRoot = null;
    await _resolveRoot();
    await _trimDiskCacheIfNeeded();
  }

  Future<void> _prefetchInternal(
    PluginSource source,
    String comicId,
    String episodeId,
    String imageUrl,
  ) async {
    try {
      await load(
        source: source,
        comicId: comicId,
        episodeId: episodeId,
        imageUrl: imageUrl,
      );
    } catch (_) {}
  }

  Future<Uint8List> _loadInternal({
    required String cacheKey,
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final file = await _fileForKey(cacheKey);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      await _capturePageHeight(imageUrl, bytes);
      _remember(cacheKey, bytes);
      return bytes;
    }

    final bytes = await PluginImageLoader.instance.loadComicImage(
      source: source,
      comicId: comicId,
      episodeId: episodeId,
      imageUrl: imageUrl,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: false);
    await _capturePageHeight(imageUrl, bytes);
    await _trimDiskCacheIfNeeded();
    _remember(cacheKey, bytes);
    return bytes;
  }

  /// Feeds the encoded header to [PageHeightCache] (no pixel decode) so the
  /// vertical continuous list knows this page's height before it is laid out.
  ///
  /// Awaited on purpose: it is a header parse of bytes we already hold, and the
  /// reader must see the ratio before it renders the page.
  Future<void> _capturePageHeight(String imageUrl, Uint8List bytes) async {
    await PageHeightCache.instance.rememberFromBytes(imageUrl, bytes);
  }

  void _remember(String cacheKey, Uint8List bytes) {
    _memory[cacheKey] = bytes;
    _touch(cacheKey);
    while (_memoryOrder.length > _maxMemoryEntries) {
      final evictedKey = _memoryOrder.removeAt(0);
      _memory.remove(evictedKey);
    }
  }

  void _touch(String cacheKey) {
    _memoryOrder.remove(cacheKey);
    _memoryOrder.add(cacheKey);
  }

  Future<File> _fileForKey(String cacheKey) async {
    _cacheRoot ??= await _resolveRoot();
    return File(
      p.join(_cacheRoot!.path, cacheKey.substring(0, 2), '$cacheKey.bin'),
    );
  }

  Future<Directory> _resolveRoot() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDirectory.path, 'reader_cache'));
    await root.create(recursive: true);
    _cacheRoot = root;
    return root;
  }

  Future<void> _trimDiskCacheIfNeeded() async {
    final root = await _resolveRoot();
    final limitBytes =
        SettingsController.instance.readerCacheLimitMb * 1024 * 1024;
    final files = <({File file, int size, DateTime modified})>[];
    var total = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      total += stat.size;
      files.add((file: entity, size: stat.size, modified: stat.modified));
    }

    if (total <= limitBytes) {
      return;
    }

    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      if (total <= limitBytes) {
        break;
      }
      if (await entry.file.exists()) {
        await entry.file.delete();
        total -= entry.size;
      }
    }
  }

  String _cacheKey(
    String sourceKey,
    String comicId,
    String episodeId,
    String imageUrl,
  ) {
    return md5
        .convert(
          utf8.encode(
            '$_cacheVersion|$sourceKey|$comicId|$episodeId|$imageUrl',
          ),
        )
        .toString();
  }
}
