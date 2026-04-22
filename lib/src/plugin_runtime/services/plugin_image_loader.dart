import 'dart:typed_data';

import 'package:dio/dio.dart';

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

  Future<Uint8List> loadComicImage({
    required PluginSource source,
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final request = source.comic?.onImageLoad == null
        ? const PluginImageRequest()
        : await source.comic!.onImageLoad!(imageUrl, comicId, episodeId);

    return _loadBytes(imageUrl, request, allowRetry: true);
  }

  Future<Uint8List> loadThumbnail({
    required PluginSource source,
    required String imageUrl,
  }) async {
    final request = source.comic?.onThumbnailLoad == null
        ? const PluginImageRequest()
        : source.comic!.onThumbnailLoad!(imageUrl);

    return _loadBytes(imageUrl, request, allowRetry: false);
  }

  Future<Uint8List> _loadBytes(
    String fallbackUrl,
    PluginImageRequest request, {
    required bool allowRetry,
  }) async {
    final dio =
        Dio(
            BaseOptions(
              responseType: ResponseType.bytes,
              validateStatus: (_) => true,
            ),
          )
          ..interceptors.add(
            PluginCookieInterceptor(PluginRuntime.instance.cookieStore),
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

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data == null) {
        throw StateError('Image request failed: HTTP ${response.statusCode}');
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
      if (!allowRetry || request.onLoadFailed == null) {
        rethrow;
      }

      final retryConfig = await _resolve(request.onLoadFailed!.call([]));
      if (retryConfig is! Map) {
        rethrow;
      }

      return _loadBytes(
        fallbackUrl,
        _parseRequestFromDynamic(retryConfig),
        allowRetry: false,
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
