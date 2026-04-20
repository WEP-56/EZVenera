import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../plugin_runtime/models.dart';
import '../plugin_runtime/plugin_runtime.dart';

class PluginWebviewLoginPage extends StatefulWidget {
  const PluginWebviewLoginPage({required this.source, super.key});

  final PluginSource source;

  @override
  State<PluginWebviewLoginPage> createState() => _PluginWebviewLoginPageState();
}

class _PluginWebviewLoginPageState extends State<PluginWebviewLoginPage> {
  static WebViewEnvironment? _webViewEnvironment;
  static Future<WebViewEnvironment?>? _environmentFuture;

  InAppWebViewController? controller;
  double progress = 0;
  String pageTitle = 'Webview Login';
  String currentUrl = '';
  bool isCompleting = false;
  late Future<WebViewEnvironment?> _environment;

  PluginAccountCapability get account => widget.source.account!;

  @override
  void initState() {
    super.initState();
    currentUrl = account.loginWebsite ?? '';
    _environment = _ensureEnvironment();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebViewEnvironment?>(
      future: _environment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(pageTitle)),
            body: const Center(
              child: SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(pageTitle)),
            body: _LoginError(
              message: snapshot.error.toString(),
              onRetry: _retry,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                onPressed: controller == null ? null : _reload,
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload',
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: InAppWebView(
                  webViewEnvironment: snapshot.data,
                  initialUrlRequest: URLRequest(
                    url: WebUri(account.loginWebsite!),
                  ),
                  initialSettings: InAppWebViewSettings(
                    isInspectable: kDebugMode,
                  ),
                  onWebViewCreated: (nextController) {
                    controller = nextController;
                  },
                  onTitleChanged: (nextController, title) {
                    pageTitle = (title == null || title.trim().isEmpty)
                        ? 'Webview Login'
                        : title;
                    if (mounted) {
                      setState(() {});
                    }
                    _validateLogin(
                      url: currentUrl,
                      title: pageTitle,
                      controller: nextController,
                    );
                  },
                  onLoadStart: (nextController, url) {
                    currentUrl = url?.toString() ?? currentUrl;
                  },
                  onLoadStop: (nextController, url) {
                    currentUrl = url?.toString() ?? currentUrl;
                    _validateLogin(
                      url: currentUrl,
                      title: pageTitle,
                      controller: nextController,
                    );
                  },
                  shouldOverrideUrlLoading: (nextController, action) async {
                    currentUrl = action.request.url?.toString() ?? currentUrl;
                    _validateLogin(
                      url: currentUrl,
                      title: pageTitle,
                      controller: nextController,
                    );
                    return NavigationActionPolicy.ALLOW;
                  },
                  onProgressChanged: (_, nextProgress) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      progress = nextProgress / 100;
                    });
                  },
                ),
              ),
              if (progress < 1)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (isCompleting)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 32,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _validateLogin({
    required String url,
    required String title,
    required InAppWebViewController controller,
  }) async {
    if (isCompleting || account.checkLoginStatus == null) {
      return;
    }
    if (!account.checkLoginStatus!(url, title)) {
      return;
    }

    setState(() {
      isCompleting = true;
    });

    try {
      final cookies = await _loadCookies(controller, url);
      final localStorage = await _loadLocalStorage(controller);
      widget.source.data['_localStorage'] = localStorage;
      if (cookies.isNotEmpty) {
        PluginRuntime.instance.cookieStore.saveFromResponse(
          Uri.parse(url),
          cookies,
        );
      }
      widget.source.markLoggedIn();
      await widget.source.saveData();
      await widget.source.account?.onWebviewLoginSuccess?.call();
      await widget.source.saveData();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isCompleting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<List<io.Cookie>> _loadCookies(
    InAppWebViewController controller,
    String url,
  ) async {
    final uri = Uri.parse(url);
    final cookieManager = CookieManager.instance(
      webViewEnvironment: _webViewEnvironment,
    );
    final loaded = await cookieManager.getCookies(
      url: WebUri.uri(uri),
      webViewController: controller,
    );
    return loaded.map((item) {
      final cookie = io.Cookie(item.name, item.value?.toString() ?? '');
      cookie.domain = item.domain ?? uri.host;
      cookie.path = item.path ?? '/';
      cookie.secure = item.isSecure ?? false;
      cookie.httpOnly = item.isHttpOnly ?? false;
      final expiresDate = item.expiresDate;
      if (expiresDate != null) {
        cookie.expires = DateTime.fromMillisecondsSinceEpoch(expiresDate);
      }
      return cookie;
    }).toList();
  }

  Future<Map<String, dynamic>> _loadLocalStorage(
    InAppWebViewController controller,
  ) async {
    final items = await LocalStorage(controller: controller).getItems();
    final mapped = <String, dynamic>{};
    for (final item in items) {
      final key = item.key;
      if (key == null) {
        continue;
      }
      mapped[key] = item.value;
    }
    return mapped;
  }

  Future<WebViewEnvironment?> _ensureEnvironment() {
    if (!io.Platform.isWindows) {
      return Future<WebViewEnvironment?>.value(null);
    }
    if (_webViewEnvironment != null) {
      return Future<WebViewEnvironment?>.value(_webViewEnvironment);
    }
    _environmentFuture ??= _createEnvironment();
    return _environmentFuture!;
  }

  Future<WebViewEnvironment?> _createEnvironment() async {
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null || version.trim().isEmpty) {
      throw StateError('WebView2 runtime is not available on this Windows system.');
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final userDataFolder = p.join(supportDirectory.path, 'webview');
    _webViewEnvironment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: userDataFolder),
    );
    return _webViewEnvironment;
  }

  void _reload() {
    controller?.reload();
  }

  void _retry() {
    setState(() {
      _environmentFuture = null;
      _environment = _ensureEnvironment();
    });
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
