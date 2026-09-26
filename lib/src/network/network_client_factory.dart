import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;

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

  @override
  bool operator ==(Object other) =>
      other is ProxyConfig && other.mode == mode && other.url == url;

  @override
  int get hashCode => Object.hash(mode, url);
}

/// Single entry point for every outbound HTTP(S) request.
///
/// All Dio instances and the rhttp (WebDAV) adapter must be created here so
/// the proxy setting applies uniformly and reacts to settings changes
/// (REQ-006 / REQ-008).
///
/// Connection reuse: the factory keeps one shared Dio per resolved
/// [ProxyConfig]; its adapter owns the HttpClient (TCP/TLS keep-alive pool).
/// Callers with default settings share that instance directly, callers with
/// special options get `shared.clone()` which reuses the same adapter and
/// therefore the same pooled connections. Only a proxy-configuration change
/// rebuilds the shared client (REQ-007).
class NetworkClientFactory {
  NetworkClientFactory._();

  static final NetworkClientFactory instance = NetworkClientFactory._();

  Dio? _sharedDio;
  ProxyConfig? _sharedConfig;

  /// TLS trust store built from the bundled Mozilla root bundle
  /// (assets/certs/cacert.pem — the same set curl/Python certifi ship).
  ///
  /// dart:io validates certificates against the OS trust store, which on
  /// old devices (e.g. Android 8.1) misses newer roots such as Sectigo Root
  /// R46 — some CDNs (ZeroSSL) chain exclusively to them, producing
  /// CERTIFICATE_VERIFY_FAILED. Bundling keeps full certificate verification
  /// intact while staying current; it is a newer trust store, not a bypass.
  SecurityContext? _bundledRoots;
  Future<void>? _initFuture;

  /// Loads the bundled root certificates once. Awaits before the first
  /// network request (main.dart) so every client benefits from it.
  Future<void> ensureInitialized() => _initFuture ??= _loadBundledRoots();

  Future<void> _loadBundledRoots() async {
    try {
      final data = await rootBundle.load('assets/certs/cacert.pem');
      final context = SecurityContext();
      context.setTrustedCertificatesBytes(data.buffer.asUint8List());
      _bundledRoots = context;
    } catch (error) {
      // Fall back to the system trust store rather than failing startup.
      unawaited(
        AppLogger.instance.warning(
          '[network] Bundled root certificates unavailable ($error); '
          'using the system trust store',
        ),
      );
    }
  }

  /// Invalid custom-proxy URLs are warned about once per distinct URL, not
  /// once per request (a misconfigured proxy must not flood the log).
  static String? _warnedInvalidProxyUrl;

  /// Reads the current settings on every call — the settings controller is
  /// the single source of truth, so no explicit reload is needed.
  ProxyConfig resolveProxyConfig() {
    final settings = SettingsController.instance;
    final mode = settings.proxyMode;
    if (mode != ProxyMode.custom) {
      _warnedInvalidProxyUrl = null;
      return ProxyConfig(mode: mode);
    }
    final url = settings.proxyUrl.trim();
    if (!SettingsController.isValidProxyUrl(url)) {
      // An invalid custom URL must not break every request; fall back to
      // system behavior. Warn once per distinct URL.
      if (_warnedInvalidProxyUrl != url) {
        _warnedInvalidProxyUrl = url;
        unawaited(
          AppLogger.instance.warning(
            '[network] Custom proxy URL is invalid, falling back to system '
            'proxy: "$url"',
          ),
        );
      }
      return const ProxyConfig(mode: ProxyMode.system);
    }
    _warnedInvalidProxyUrl = null;
    return ProxyConfig(mode: ProxyMode.custom, url: url);
  }

  /// Returns a Dio client wired to the current proxy configuration.
  ///
  /// * [responseType] mirrors the caller's previous `BaseOptions`.
  /// * [throwOnError] false keeps the app-wide "never throw for status"
  ///   convention (`validateStatus: (_) => true`); set true for callers that
  ///   relied on Dio's default 2xx-only validation (update checks).
  /// * [interceptors] are appended after the logging interceptor. They live
  ///   on the returned instance only (use [interceptorsKey] if you want them
  ///   shared across calls — pass a stable identity such as the cookie store).
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
    if (_sharedDio == null || _sharedConfig != config) {
      final previous = _sharedDio;
      _sharedDio = _buildSharedDio(config);
      _sharedConfig = config;
      if (previous != null) {
        // Gracefully retire the previous client after a grace period:
        // in-flight requests finish and pooled idle sockets close. Switching
        // back inside the window simply builds a fresh client (cheap).
        unawaited(
          Future<void>.delayed(const Duration(seconds: 30)).then((_) {
            try {
              previous.httpClientAdapter.close(force: false);
            } catch (_) {
              // Already closed or adapter-specific failure; nothing to do.
            }
          }),
        );
      }
    }
    final shared = _sharedDio!;

    final isDefaultCall =
        responseType == ResponseType.plain &&
        !throwOnError &&
        interceptors == null &&
        !logSuccessResponses;
    if (isDefaultCall) {
      return shared;
    }

    // clone() shares the adapter (and its pooled connections) while giving
    // this caller its own options/interceptors. A fresh BaseOptions is passed
    // because Dio.clone otherwise reuses the shared options instance.
    final dio = shared.clone(
      options: BaseOptions(
        responseType: responseType,
        validateStatus: throwOnError ? null : (_) => true,
      ),
    );
    if (logSuccessResponses) {
      dio.interceptors.add(_NetworkLogInterceptor(logSuccess: true));
    }
    if (interceptors != null) {
      dio.interceptors.addAll(interceptors);
    }
    return dio;
  }

  Dio _buildSharedDio(ProxyConfig config) {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    )..interceptors.add(_NetworkLogInterceptor(logSuccess: false));
    dio.httpClientAdapter = _createAdapter(config);
    return dio;
  }

  HttpClientAdapter _createAdapter(ProxyConfig config) {
    return IOHttpClientAdapter(
      createHttpClient: () {
        // null falls back to the system trust store if the bundle failed to
        // load (see [_loadBundledRoots]).
        final client = HttpClient(context: _bundledRoots);
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
/// successful requests only when the caller opts in. Stateless, so a single
/// instance can safely be shared (and copied by Dio.clone).
class _NetworkLogInterceptor extends Interceptor {
  _NetworkLogInterceptor({required this.logSuccess});

  final bool logSuccess;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final request = response.requestOptions;
    if (response.statusCode == 407) {
      // A proxy requiring credentials this client cannot send: dart:io's
      // `PROXY host:port` carries no userinfo (ADR-NW-2), so an
      // authenticated proxy only works for the rhttp/WebDAV path. Call it
      // out explicitly instead of letting it surface as a generic failure.
      unawaited(
        AppLogger.instance.warning(
          '[network] ${request.method} ${request.uri} -> 407: proxy '
          'requires authentication; proxy credentials are currently only '
          'applied to WebDAV (rhttp) requests (ADR-NW-2)',
        ),
      );
    }
    if (logSuccess) {
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
