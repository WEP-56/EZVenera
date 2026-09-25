import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/json_file_store.dart';

/// Remembers the intrinsic aspect ratio (height / width) of reader page
/// images, keyed by image URL.
///
/// Why this exists: vertical continuous mode has to reserve each item's height
/// *before* the image is decoded. If the reserved height is a guess (or only
/// known after layout), the item changes size once the image arrives, which
/// makes `ScrollablePositionedList` throw away its leading-edge bookkeeping and
/// re-anchor — the list visibly jumps and rolls back when scrolling up, and a
/// mid-chapter resume (where every item above is still unmeasured) is the worst
/// case. With the ratio on hand the height is correct from the very first
/// frame, so nothing ever resizes and nothing ever re-anchors.
///
/// Ratios are read straight from the encoded header via
/// [ui.ImageDescriptor] — no pixel decode, no network — and persisted so a
/// chapter that has been read once is exact on every later visit.
class PageHeightCache {
  PageHeightCache._();

  static final PageHeightCache instance = PageHeightCache._();

  /// Sanity bounds on a measured ratio (height / width).
  ///
  /// These are *header* sanity checks, not layout preferences — they only exist
  /// to catch a buffer that was mis-parsed into a nonsense number. They must
  /// therefore stay well clear of any legitimate page shape:
  ///
  /// * Upper: webtoon (条漫) pages are long vertical strips. The common canvas
  ///   is 800px wide, a chapter runs 20–30 of them, and several sources ship a
  ///   whole chapter as one merged image — 800x25000 is real, i.e. ratio ~31,
  ///   and the extreme end reaches ~110. A limit of 20 would silently reject
  ///   those, which is worse than a wrong estimate: the page would fall back to
  ///   a normal-comic median and render *shrunk* inside a short box.
  /// * Lower: double-page spreads. They are wide but nowhere near 10:1.
  static const double _minRatio = 0.1;
  static const double _maxRatio = 128;

  /// Upper bound on persisted entries (~20000 pages). Oldest are dropped first.
  static const int _maxEntries = 20000;

  /// Used when a page has never been measured: 1.5 is the common comic page
  /// shape (2:3). Only ever applies to pages that are not visible yet.
  static const double fallbackRatio = 1.5;

  final Map<String, double> _ratios = <String, double>{};
  final List<String> _order = <String>[];
  JsonFileStore? _store;
  bool _initializing = false;
  bool _initialized = false;
  bool _dirty = false;
  Timer? _flushTimer;
  double? _globalMedian;

  bool get isInitialized => _initialized;

  /// Median ratio across everything measured so far, or [fallbackRatio] when
  /// nothing has been measured yet.
  ///
  /// Used to estimate pages that have never been measured. A per-comic median
  /// would be tighter, but comic pages cluster closely enough that this is
  /// already within a few percent — and the estimate only ever applies to pages
  /// that are not on screen yet.
  double globalMedianRatio() {
    final cached = _globalMedian;
    if (cached != null) {
      return cached;
    }
    if (_ratios.isEmpty) {
      // Do not cache: an empty table can still gain entries this session.
      return fallbackRatio;
    }
    final values = _ratios.values.toList()..sort();
    final median = values[values.length ~/ 2];
    _globalMedian = median;
    return median;
  }

  /// Ratio (height / width) for [imageUrl], or null when never measured.
  double? ratioFor(String imageUrl) {
    final key = _key(imageUrl);
    if (key == null) {
      return null;
    }
    return _ratios[key];
  }

  /// Starts loading the persisted table. Cheap to call repeatedly.
  Future<void> initialize() async {
    if (_initialized || _initializing) {
      return;
    }
    _initializing = true;
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final root = Directory(p.join(supportDirectory.path, 'reader_cache'));
      await root.create(recursive: true);
      final store = JsonFileStore(File(p.join(root.path, 'page_heights.json')));
      _store = store;
      final decoded = await store.read();
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! num) {
          continue;
        }
        final ratio = value.toDouble();
        if (!_isSane(ratio) || _ratios.containsKey(entry.key)) {
          continue;
        }
        _ratios[entry.key] = ratio;
        _order.add(entry.key);
      }
      _trimToLimit();
    } catch (_) {
      // A missing or unreadable height file only costs us one session of
      // estimated heights; it must never block the reader.
    } finally {
      _initializing = false;
      _initialized = true;
    }
  }

  /// Reads the header of [bytes] and remembers the ratio for [imageUrl].
  ///
  /// Returns the ratio, or null when the format could not be parsed (in which
  /// case the caller keeps its estimate and the page still renders).
  Future<double?> rememberFromBytes(String imageUrl, Uint8List bytes) async {
    final key = _key(imageUrl);
    if (key == null) {
      return null;
    }
    final known = _ratios[key];
    if (known != null) {
      return known;
    }
    await initialize();
    final ratio = await _measure(bytes);
    if (ratio == null) {
      return null;
    }
    _ratios[key] = ratio;
    _order.add(key);
    _trimToLimit();
    _dirty = true;
    _scheduleFlush();
    return ratio;
  }

  /// Writes the table out now (used when the reader is closed).
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }

  static Future<double?> _measure(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) {
        return null;
      }
      final ratio = height / width;
      return _isSane(ratio) ? ratio : null;
    } catch (_) {
      // Unsupported/corrupt header: caller falls back to its estimate.
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static bool _isSane(double ratio) =>
      ratio.isFinite && ratio >= _minRatio && ratio <= _maxRatio;

  static String? _key(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return md5.convert(utf8.encode(trimmed)).toString();
  }

  void _trimToLimit() {
    while (_order.length > _maxEntries) {
      final dropped = _order.removeAt(0);
      _ratios.remove(dropped);
      _dirty = true;
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final store = _store;
    if (store == null || !_dirty) {
      return;
    }
    _dirty = false;
    try {
      await store.write(<String, dynamic>{
        for (final entry in _ratios.entries) entry.key: entry.value,
      });
    } catch (_) {
      // Best effort: heights are a cache, never a correctness requirement.
    }
  }
}
