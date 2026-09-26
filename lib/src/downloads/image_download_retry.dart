import 'dart:async';
import 'dart:typed_data';

import '../logging/app_logger.dart';

/// Fetches one page image with bounded retries and a response-body sanity
/// check (REQ-010).
///
/// Transient failures (socket resets, gateways, momentary loss of network)
/// are retried with exponential backoff (1s, 2s, ...). Empty bodies and
/// non-image payloads (anti-scraping gateways answering 200 with an HTML
/// error page) count as failures so they are retried and, if persistent,
/// accounted as a failed page instead of being cached as an image. Returns
/// null only after all attempts are exhausted, letting the caller keep the
/// overall download alive.
Future<Uint8List?> fetchImageWithRetry(
  Future<Uint8List> Function() fetch, {
  int maxRetries = 2,
  Future<void> Function(Duration delay)? sleep,
  String? debugLabel,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      final bytes = await fetch();
      if (bytes.isNotEmpty && looksLikeImage(bytes)) {
        return bytes;
      }
      lastError = StateError(
        bytes.isEmpty
            ? 'Empty image body'
            : 'Response body is not a recognized image',
      );
    } catch (error) {
      lastError = error;
    }
    if (attempt < maxRetries) {
      final backoff = Duration(seconds: 1 << attempt);
      unawaited(
        AppLogger.instance.warning(
          '[download] Attempt ${attempt + 1} failed'
          '${debugLabel == null ? '' : ' for $debugLabel'}: $lastError; '
          'retrying in ${backoff.inSeconds}s',
        ),
      );
      if (sleep != null) {
        await sleep(backoff);
      } else {
        await Future<void>.delayed(backoff);
      }
    }
  }
  return null;
}

/// Light-weight magic-byte sniffing: the common page-image formats are
/// whitelisted, anything else (HTML error pages, JSON, text challenges) is
/// treated as a failure so it is retried and never lands in the image
/// cache. Public for testing; extend the list if a source serves a format
/// not covered here.
bool looksLikeImage(Uint8List bytes) {
  if (bytes.length < 12) {
    return false;
  }
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return true;
  }
  // GIF87a/GIF89a: "GIF8"
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
    return true;
  }
  // WebP: "RIFF"...."WEBP"
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  // BMP: "BM"
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  // AVIF: "....ftyp" followed by brand "avif"/"avis"
  if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (brand == 'avif' || brand == 'avis') {
      return true;
    }
  }
  return false;
}
