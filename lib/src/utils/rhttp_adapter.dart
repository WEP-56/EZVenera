import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import '../network/network_client_factory.dart';
import '../settings/settings_controller.dart';

/// Dio adapter used by upstream Venera for WebDAV requests.
class RHttpAdapter implements HttpClientAdapter {
  static final Future<void> _initialized = rhttp.Rhttp.init();

  /// Settings are resolved per request so proxy changes apply immediately
  /// (REQ-006 / REQ-007). The previous `static const` configuration made the
  /// WebDAV path immune to any settings change.
  static rhttp.ClientSettings _buildSettings() {
    final config = NetworkClientFactory.instance.resolveProxyConfig();
    // null proxySettings keeps rhttp's default behavior: follow the system
    // proxy. That matches ProxyMode.system.
    rhttp.ProxySettings? proxySettings;
    if (config.usesCustomProxy) {
      proxySettings = rhttp.ProxySettings.proxy(config.url.trim());
    } else if (config.mode == ProxyMode.off) {
      proxySettings = const rhttp.ProxySettings.noProxy();
    }
    return rhttp.ClientSettings(
      redirectSettings: rhttp.RedirectSettings.limited(5),
      timeoutSettings: rhttp.TimeoutSettings(
        connectTimeout: Duration(seconds: 15),
        keepAliveTimeout: Duration(seconds: 60),
        keepAlivePing: Duration(seconds: 30),
      ),
      throwOnStatusCode: false,
      proxySettings: proxySettings,
    );
  }

  static Future<void> initialize() => _initialized;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await initialize();
    final response = await rhttp.Rhttp.request(
      method: rhttp.HttpMethod(options.method),
      url: options.uri.toString(),
      settings: _buildSettings(),
      expectBody: rhttp.HttpExpectBody.stream,
      body: requestStream == null ? null : rhttp.HttpBody.stream(requestStream),
      headers: rhttp.HttpHeaders.rawMap(
        Map<String, String>.fromEntries(
          options.headers.entries.map(
            (entry) => MapEntry(entry.key, entry.value.toString().trim()),
          ),
        ),
      ),
    );
    if (response is! rhttp.HttpStreamResponse) {
      throw StateError('Invalid HTTP response type: ${response.runtimeType}');
    }

    final headers = <String, List<String>>{};
    for (final entry in response.headers) {
      headers
          .putIfAbsent(entry.$1.toLowerCase(), () => <String>[])
          .add(entry.$2);
    }
    return ResponseBody(
      response.body,
      response.statusCode,
      headers: headers,
      isRedirect: false,
    );
  }
}
