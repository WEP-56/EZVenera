import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';

class PluginCookieStore {
  PluginCookieStore(this.path);

  final String path;
  late final Database _db = sqlite3.open(path);

  void initialize() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cookies (
        name TEXT NOT NULL,
        value TEXT NOT NULL,
        domain TEXT NOT NULL,
        path TEXT,
        expires INTEGER,
        secure INTEGER,
        http_only INTEGER,
        PRIMARY KEY (name, domain, path)
      );
    ''');
  }

  void saveFromResponse(Uri uri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      _db.execute(
        '''
        INSERT OR REPLACE INTO cookies (name, value, domain, path, expires, secure, http_only)
        VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
        [
          cookie.name,
          cookie.value,
          cookie.domain ?? uri.host,
          cookie.path ?? '/',
          cookie.expires?.millisecondsSinceEpoch,
          cookie.secure ? 1 : 0,
          cookie.httpOnly ? 1 : 0,
        ],
      );
    }
  }

  void saveFromSetCookieHeaders(Uri uri, List<String> headers) {
    final cookies = <Cookie>[];
    for (final header in headers) {
      try {
        cookies.add(Cookie.fromSetCookieValue(header));
      } catch (_) {
        continue;
      }
    }
    saveFromResponse(uri, cookies);
  }

  List<Cookie> loadForRequest(Uri uri) {
    final domains = _acceptedDomains(uri.host);
    final cookies = <Cookie>[];

    for (final domain in domains) {
      final rows = _db.select(
        '''
        SELECT name, value, domain, path, expires, secure, http_only
        FROM cookies
        WHERE domain = ?;
      ''',
        [domain],
      );

      for (final row in rows) {
        final expiresMillis = row['expires'] as int?;
        final expires = expiresMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresMillis);
        if (expires != null && expires.isBefore(DateTime.now())) {
          _db.execute(
            '''
            DELETE FROM cookies
            WHERE name = ? AND domain = ? AND path = ?;
          ''',
            [row['name'], row['domain'], row['path']],
          );
          continue;
        }

        final path = row['path'] as String? ?? '/';
        if (!_pathMatches(uri.path, path)) {
          continue;
        }

        cookies.add(
          Cookie(row['name'] as String, row['value'] as String)
            ..domain = row['domain'] as String
            ..path = path
            ..expires = expires
            ..secure = row['secure'] == 1
            ..httpOnly = row['http_only'] == 1,
        );
      }
    }

    return cookies;
  }

  String buildCookieHeader(Uri uri) {
    final unique = <String, Cookie>{};

    for (final cookie in loadForRequest(uri)) {
      unique[cookie.name] = cookie;
    }

    return unique.values
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  void deleteForUri(Uri uri) {
    for (final domain in _acceptedDomains(uri.host)) {
      _db.execute('DELETE FROM cookies WHERE domain = ?;', [domain]);
    }
  }

  List<String> _acceptedDomains(String host) {
    final parts = host.split('.');
    final values = <String>[host];
    for (var index = 0; index < parts.length - 1; index++) {
      values.add('.${parts.sublist(index).join('.')}');
    }
    return values;
  }

  bool _pathMatches(String requestPath, String cookiePath) {
    if (cookiePath == '/' || cookiePath == requestPath) {
      return true;
    }
    if (cookiePath.endsWith('/')) {
      return requestPath.startsWith(cookiePath);
    }
    return requestPath.startsWith(cookiePath);
  }
}

class PluginCookieInterceptor extends Interceptor {
  PluginCookieInterceptor(this.store);

  final PluginCookieStore store;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cookies = store.buildCookieHeader(options.uri);
    if (cookies.isNotEmpty) {
      final existing = options.headers['cookie'];
      options.headers['cookie'] = existing == null
          ? cookies
          : '$existing; $cookies';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    store.saveFromSetCookieHeaders(
      response.requestOptions.uri,
      response.headers['set-cookie'] ?? const [],
    );
    handler.next(response);
  }
}
