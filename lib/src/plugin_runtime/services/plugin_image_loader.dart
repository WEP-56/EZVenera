import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../logging/app_logger.dart';
import '../../network/network_client_factory.dart';
import '../models.dart';
import '../plugin_runtime.dart';
import '../storage/cookie_store.dart';
import 'plugin_image_modifier.dart';

class PluginImageLoader {
  PluginImageLoader._();

  static final PluginImageLoader instance = PluginImageLoader._();

  static const _defaultHeaders = <String, dynamic>{
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
  };

  /// Image CDNs occasionally answer 5xx for single requests (origin hiccup,
  /// flaky device networks). Retry the identical request briefly before
  /// surfacing the failure or invoking the plugin's onLoadFailed.
  static const _transientRetryLimit = 2;
  static const _transientRetryDelay = Duration(milliseconds: 600);

  Future<Uint8List> loadComicImage({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final request = source.comic?.onImageLoad == null
        ? const PluginImageRequest()
        : await source.comic!.onImageLoad!(imageUrl, comicId, episodeId);

    return _loadBytes(imageUrl, request, remainingRetries: 5);
  }

  Future<Uint8List> loadThumbnail({
    required PluginSource source,
    required String imageUrl,
  }) async {
    final request = source.comic?.onThumbnailLoad == null
        ? const PluginImageRequest()
        : source.comic!.onThumbnailLoad!(imageUrl);

    return _loadBytes(imageUrl, request, remainingRetries: 0);
  }

  Future<Uint8List> _loadBytes(
    String fallbackUrl,
    PluginImageRequest request, {
    required int remainingRetries,
    int transientRetries = _transientRetryLimit,
  }) async {
    // Created per request so proxy settings apply immediately (REQ-007).
    final dio = NetworkClientFactory.instance.httpClient(
      responseType: ResponseType.bytes,
      interceptors: [PluginCookieInterceptor(PluginRuntime.instance.cookieStore)],
    );

    try {
      final url = _normalizeUrl(request.url ?? fallbackUrl);
      final response = await dio.request<List<int>>(
        url,
        data: request.data,
        options: Options(
          method: request.method ?? 'GET',
          headers: {..._defaultHeaders, ...request.headers},
        ),
      );

      final code = response.statusCode;
      if (code == null ||
          code < 200 ||
          code >= 300 ||
          response.data == null) {
        // 5xx is treated as transient: retry the identical request before
        // failing the page (and before the plugin's onLoadFailed gets a say).
        if (code != null && code >= 500 && transientRetries > 0) {
          unawaited(
            AppLogger.instance.warning(
              '[image] GET $url -> $code, retrying ($transientRetries left)',
            ),
          );
          await Future<void>.delayed(_transientRetryDelay);
          return await _loadBytes(
            fallbackUrl,
            request,
            remainingRetries: remainingRetries,
            transientRetries: transientRetries - 1,
          );
        }
        throw StateError('Image request failed: HTTP ${code ?? 'null'}: $url');
      }

      var bytes = Uint8List.fromList(response.data!);
      if (request.onResponse != null) {
        final transformed = await _resolve(request.onResponse!.call([bytes]));
        if (transformed is Uint8List) {
          bytes = transformed;
        } else if (transformed is List<int>) {
          bytes = Uint8List.fromList(transformed);
        }
      }

      if (request.modifyImageScript case final script? when script.isNotEmpty) {
        bytes = await PluginImageModifier.instance.apply(bytes, script);
      }

      return bytes;
    } catch (error) {
      if (remainingRetries <= 0 || request.onLoadFailed == null) {
        rethrow;
      }

      final retryConfig = await _resolve(request.onLoadFailed!.call([]));
      if (retryConfig is! Map) {
        rethrow;
      }

      return _loadBytes(
        fallbackUrl,
        _parseRequestFromDynamic(retryConfig),
        remainingRetries: remainingRetries - 1,
      );
    }
  }

  PluginImageRequest _parseRequestFromDynamic(Map<dynamic, dynamic> map) {
    JSAutoFreeFunction? onResponse;
    final rawOnResponse = map['onResponse'];
    if (rawOnResponse is! JSAutoFreeFunction && rawOnResponse != null) {
      onResponse = null;
    } else {
      onResponse = rawOnResponse as JSAutoFreeFunction?;
    }

    JSAutoFreeFunction? onLoadFailed;
    final rawOnLoadFailed = map['onLoadFailed'];
    if (rawOnLoadFailed is! JSAutoFreeFunction && rawOnLoadFailed != null) {
      onLoadFailed = null;
    } else {
      onLoadFailed = rawOnLoadFailed as JSAutoFreeFunction?;
    }

    return PluginImageRequest(
      url: map['url']?.toString(),
      method: map['method']?.toString(),
      data: map['data'],
      headers: Map<String, dynamic>.from(
        map['headers'] ?? const <String, dynamic>{},
      ),
      onResponse: onResponse,
      modifyImageScript: map['modifyImage']?.toString(),
      onLoadFailed: onLoadFailed,
    );
  }

  String _normalizeUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return url;
  }

  Future<dynamic> _resolve(dynamic value) async {
    if (value is Future) {
      return await value;
    }
    return value;
  }
}
