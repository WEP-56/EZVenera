import 'dart:async';
import 'dart:typed_data';

import '../logging/app_logger.dart';

/// Fetches one page image with bounded retries and a non-empty-body check
/// (REQ-010).
///
/// Transient failures (socket resets, gateways, momentary loss of network)
/// are retried with exponential backoff (1s, 2s, ...). Returns null only
/// after all attempts are exhausted, letting the caller keep the overall
/// download alive and account for the failed page instead of aborting the
/// whole job.
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
      if (bytes.isNotEmpty) {
        return bytes;
      }
      lastError = StateError('Empty image body');
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
