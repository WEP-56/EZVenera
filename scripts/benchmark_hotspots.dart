// Baseline benchmark for the Rust-evaluation hotspots (REQ-013, TASK-401).
//
// Measures the three candidate hotspots identified in design.md D-4:
//   H1 — image cache key hashing (md5 over a small string)
//   H2 — disk-cache trim scan (recursive list + stat + sort by mtime)
//   H3 — pure-Dart pixel loops in PluginImageModifier
//        (copyAndRotate90 + copyRange over a comic-page-sized RGBA buffer)
//
// Run (AOT, closest to production): from the repo root,
//   dart compile exe scripts/benchmark_hotspots.dart -o /tmp/ezv_bench
//   /tmp/ezv_bench
// Or JIT (quick look): dart run scripts/benchmark_hotspots.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Duration measure(String name, int iterations, void Function(int i) body) {
  // Warmup.
  body(-1);
  final watch = Stopwatch();
  watch.start();
  for (var i = 0; i < iterations; i++) {
    body(i);
  }
  watch.stop();
  final perOp = watch.elapsedMicroseconds / iterations;
  stdout.writeln(
    '$name: total ${watch.elapsedMilliseconds} ms / $iterations ops '
    '= ${perOp.toStringAsFixed(2)} µs/op',
  );
  return watch.elapsed;
}

Future<void> main(List<String> args) async {
  final mode = Platform.executable.contains('dart')
      ? 'JIT (dart run)'
      : 'AOT (compiled exe)';
  stdout.writeln('== EZVenera hotspot baseline — Dart $mode ==');

  // H1 — cache key: md5 of '<version>|<source>|<comic>|<episode>|<url>'.
  const keySample =
      'v2|ecchiw|e0a1f2|cb3aa919|https://img.example.com/pages/0123.jpg?p=1';
  measure('H1 md5 cache key', 20000, (i) {
    md5.convert(utf8.encode('$keySample|$i'));
  });

  // H2 — disk cache trim scan: create a realistic cache tree (2000 files,
  // 256 subdirs), then replicate _trimDiskCacheIfNeeded's scan+stat+sort.
  final cacheDir =
      await Directory.systemTemp.createTemp('ezv_bench_cache');
  try {
    const files = 2000;
    for (var i = 0; i < files; i++) {
      final sub = Directory('${cacheDir.path}/${(i % 64).toRadixString(16)}');
      sub.createSync(recursive: true);
      File('${sub.path}/$i.bin').writeAsBytesSync(
        Uint8List(2048),
        flush: false,
      );
    }
    measure('H2 cache trim scan (stat+sort, 2000 files)', 5, (i) {
      final entries = <({File file, int size, DateTime modified})>[];
      final list = cacheDir.listSync(recursive: true, followLinks: false);
      for (final entity in list) {
        if (entity is! File) continue;
        final stat = entity.statSync();
        entries.add((file: entity, size: stat.size, modified: stat.modified));
      }
      entries.sort((a, b) => a.modified.compareTo(b.modified));
    });
  } finally {
    cacheDir.deleteSync(recursive: true);
  }

  // H3 — pixel ops on a 1200x1800 RGBA (Uint32List) comic page.
  const w = 1200, h = 1800;
  final page = Uint32List(w * h);
  var rng = 0x12345678;
  for (var i = 0; i < page.length; i++) {
    rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF;
    page[i] = rng;
  }
  measure('H3 copyAndRotate90 (1200x1800)', 20, (i) {
    final out = Uint32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[x * h + h - y - 1] = page[y * w + x];
      }
    }
  });
  measure('H3 copyRange (600x900 region)', 40, (i) {
    final out = Uint32List(600 * 900);
    for (var y = 0; y < 900; y++) {
      for (var x = 0; x < 600; x++) {
        out[y * 600 + x] = page[(y + 100) * w + x + 50];
      }
    }
  });

  stdout.writeln('== done ==');
}
