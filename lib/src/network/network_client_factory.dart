import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../logging/app_logger.dart';
import '../settings/settings_controller.dart';

/// Resolved proxy configuration for outbound requests.
///
/// Resolved fresh from [SettingsController] before every request so proxy
/// changes apply on the next request without any reload signal (REQ-007).
class ProxyConfig {
  const ProxyConfig({required this.mode, this.url = ''});

  final ProxyMode mode;

  /// The raw user-provided URL when [mode] is [ProxyMode.custom].
  final String url;

  bool get usesCustomProxy =>
      mode == ProxyMode.custom && SettingsController.isValidProxyUrl(url);

  /// `host:port` for `HttpClient.findProxy`, or null when not custom/invalid.
  String? get customAuthority => usesCustomProxy
      ? SettingsController.customProxyAuthority(url)
      : null;
}

/// Single entry point for every outbound HTTP(S) request.
///
/// All Dio instances and the rhttp (WebDAV) adapter must be created here so
/// the proxy setting applies uniformly and reacts to settings changes
/// (REQ-006 / REQ-008). Instances are cheap; create one per request batch
/// instead of caching, so config changes are never sticky.
class NetworkClientFactory {
  NetworkClientFactory._();

  static final NetworkClientFactory instance = NetworkClientFactory._();

  /// Reads the current settings on every call — the settings controller is
  /// the single source of truth, so no explicit reload is needed.
  ProxyConfig resolveProxyConfig() {
    final settings = SettingsController.instance;
    final mode = settings.proxyMode;
    if (mode != ProxyMode.custom) {
      return ProxyConfig(mode: mode);
    }
    final url = settings.proxyUrl.trim();
    if (!SettingsController.isValidProxyUrl(url)) {
      // An invalid custom URL must not break every request; fall back to
      // system behavior and surface the misconfiguration in the log.
      unawaited(
        AppLogger.instance.warning(
          '[network] Custom proxy URL is invalid, falling back to system '
          'proxy: "$url"',
        ),
      );
      return const ProxyConfig(mode: ProxyMode.system);
    }
    return ProxyConfig(mode: ProxyMode.custom, url: url);
  }

  /// Creates a Dio client wired to the current proxy configuration.
  ///
  /// * [responseType] mirrors the caller's previous `BaseOptions`.
  /// * [throwOnError] false keeps the app-wide "never throw for status"
  ///   convention (`validateStatus: (_) => true`); set true for callers that
  ///   relied on Dio's default 2xx-only validation (update checks).
  /// * [interceptors] are appended after the logging interceptor.
  /// * [logSuccessResponses] records successful requests in the app log;
  ///   failures are always logged. Keep it off for high-frequency calls
  ///   such as image loading.
  Dio httpClient({
    ResponseType responseType = ResponseType.plain,
    bool throwOnError = false,
    List<Interceptor>? interceptors,
    bool logSuccessResponses = false,
  }) {
    final config = resolveProxyConfig();
    final dio = Dio(
      BaseOptions(
        responseType: responseType,
        validateStatus: throwOnError ? null : (_) => true,
      ),
    )..interceptors.add(_NetworkLogInterceptor(logSuccess: logSuccessResponses));
    dio.httpClientAdapter = _createAdapter(config);
    if (interceptors != null) {
      dio.interceptors.addAll(interceptors);
    }
    return dio;
  }

  HttpClientAdapter _createAdapter(ProxyConfig config) {
    return IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        switch (config.mode) {
          case ProxyMode.custom:
            final authority = config.customAuthority;
            client.findProxy = (uri) =>
                authority == null ? 'DIRECT' : 'PROXY $authority';
          case ProxyMode.off:
            // Explicit direct: do not inherit environment proxies.
            client.findProxy = (uri) => 'DIRECT';
          case ProxyMode.system:
            client.findProxy = HttpClient.findProxyFromEnvironment;
        }
        return client;
      },
    );
  }
}

/// Structured network logging (REQ-012). Failures always land in the log;
/// successful requests only when the caller opts in.
class _NetworkLogInterceptor extends Interceptor {
  _NetworkLogInterceptor({required this.logSuccess});

  final bool logSuccess;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (logSuccess) {
      final request = response.requestOptions;
      unawaited(
        AppLogger.instance.info(
          '[network] ${request.method} ${request.uri} '
          '-> ${response.statusCode}',
        ),
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final request = err.requestOptions;
    unawaited(
      AppLogger.instance.warning(
        '[network] ${request.method} ${request.uri} failed: '
        '${err.type.name} ${err.message ?? ''}',
      ),
    );
    handler.next(err);
  }
}
