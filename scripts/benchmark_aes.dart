// Baseline benchmark for the plugin crypto path (ADR-RT-1 follow-up, P-1).
//
// Measures pointycastle AES throughput for the block-cipher modes exposed to
// plugins via the JS `convert` bridge (PluginJsEngine._processBlockCipher):
//   aes-ecb / aes-cbc
// at payload sizes representative of plugin usage:
//   16 KB  — typical encrypted API/JSON response
//   256 KB — large catalog payload
//   1 MB   — encrypted image blob (worst case per page)
//
// The measured loop mirrors the engine exactly: a fresh cipher is built and
// initialized per call, then processed block-by-block with no padding.
//
// Run (AOT, closest to production): from the repo root,
//   dart compile exe scripts/benchmark_aes.dart -o /tmp/ezv_aes_bench
//   /tmp/ezv_aes_bench
// Or JIT (quick look): dart run scripts/benchmark_aes.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';

Uint8List aesProcess(
  String mode,
  Uint8List input,
  Uint8List key,
  bool encrypt,
) {
  final BlockCipher cipher = switch (mode) {
    'ECB' => ECBBlockCipher(AESEngine()),
    'CBC' => CBCBlockCipher(AESEngine()),
    _ => throw UnsupportedError('unsupported mode: $mode'),
  };
  cipher.init(
    encrypt,
    mode == 'CBC'
        ? ParametersWithIV(KeyParameter(key), Uint8List(16))
        : KeyParameter(key),
  );
  final output = Uint8List(input.length);
  var offset = 0;
  while (offset < input.length) {
    offset += cipher.processBlock(input, offset, output, offset);
  }
  return output;
}

void measure(
  String mode,
  Uint8List input,
  Uint8List key,
  int iterations,
) {
  // Warmup + round-trip sanity check.
  final encrypted = aesProcess(mode, input, key, true);
  final decrypted = aesProcess(mode, encrypted, key, false);
  for (var i = 0; i < input.length; i++) {
    if (decrypted[i] != input[i]) {
      throw StateError('$mode round-trip mismatch at byte $i');
    }
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    aesProcess(mode, input, key, true);
  }
  watch.stop();
  final encryptMs = watch.elapsedMicroseconds / iterations / 1000;

  watch
    ..reset()
    ..start();
  for (var i = 0; i < iterations; i++) {
    aesProcess(mode, encrypted, key, false);
  }
  watch.stop();
  final decryptMs = watch.elapsedMicroseconds / iterations / 1000;

  final mb = input.length / (1024 * 1024);
  stdout.writeln(
    '$mode @ ${_fmtSize(input.length)}: '
    'encrypt ${encryptMs.toStringAsFixed(2)} ms/op '
    '(${(mb / (encryptMs / 1000)).toStringAsFixed(1)} MB/s), '
    'decrypt ${decryptMs.toStringAsFixed(2)} ms/op '
    '(${(mb / (decryptMs / 1000)).toStringAsFixed(1)} MB/s)',
  );
}

String _fmtSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${bytes ~/ (1024 * 1024)} MB';
  return '${bytes ~/ 1024} KB';
}

void main() {
  final mode = Platform.executable.contains('dart')
      ? 'JIT (dart run)'
      : 'AOT (compiled exe)';
  stdout.writeln('== EZVenera plugin AES baseline — pointycastle, $mode ==');

  final rng = Random(42);
  final key = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  final payloads = <int, int>{
    16 * 1024: 2000,
    256 * 1024: 200,
    1024 * 1024: 40,
  };

  for (final entry in payloads.entries) {
    final input = Uint8List(entry.key);
    for (var i = 0; i < input.length; i++) {
      input[i] = rng.nextInt(256);
    }
    measure('ECB', input, key, entry.value);
    measure('CBC', input, key, entry.value);
  }
}
