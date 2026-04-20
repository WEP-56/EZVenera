import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:uuid/uuid.dart';

import '../engine/js_pool.dart';
import '../models.dart';
import '../storage/cookie_store.dart';
import '../storage/plugin_data_store.dart';

class PluginJsEngine {
  PluginJsEngine({
    required this.dataStore,
    required this.cookieStore,
    required this.appVersion,
  });

  final PluginDataStore dataStore;
  final PluginCookieStore cookieStore;
  final String appVersion;

  FlutterQjs? _engine;
  Dio? _dio;
  bool _initialized = false;
  final Map<String, PluginSource> _sources = {};
  final Map<int, _DocumentWrapper> _documents = {};
  Uint8List? _initJsCache;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    _dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    )..interceptors.add(PluginCookieInterceptor(cookieStore));

    _engine = FlutterQjs()..dispatch();
    final setGlobal = _engine!.evaluate(
      '(key, value) => { this[key] = value; }',
    );
    (setGlobal as JSInvokable)(['sendMessage', _onMessage]);
    setGlobal(['appVersion', appVersion]);
    setGlobal.free();

    final buffer = await rootBundle.load('assets/init.js');
    _initJsCache = buffer.buffer.asUint8List();
    _engine!.evaluate(utf8.decode(_initJsCache!), name: '<init>');

    _initialized = true;
  }

  void registerSource(PluginSource source) {
    _sources[source.key] = source;
  }

  PluginSource? findSource(String key) => _sources[key];

  void resetSources() {
    _sources.clear();
    if (_initialized) {
      _engine!.evaluate('ComicSource.sources = {};');
    }
  }

  dynamic runCode(String code, [String? name]) {
    if (!_initialized) {
      throw StateError('PluginJsEngine is not initialized.');
    }
    return _engine!.evaluate(code, name: name);
  }

  Object? _onMessage(dynamic message) {
    if (message is! Map<dynamic, dynamic>) {
      return null;
    }

    final method = message['method'];
    if (method is! String) {
      return null;
    }

    switch (method) {
      case 'log':
        return null;
      case 'load_data':
        final source = _sources[message['key']];
        return source?.data[message['data_key']];
      case 'save_data':
        return _saveSourceData(message);
      case 'delete_data':
        return _deleteSourceData(message);
      case 'http':
        return _handleHttp(Map<String, dynamic>.from(message));
      case 'html':
        return _handleHtml(Map<String, dynamic>.from(message));
      case 'convert':
        return _handleConvert(Map<String, dynamic>.from(message));
      case 'random':
        return _random(
          (message['min'] as num?) ?? 0,
          (message['max'] as num?) ?? 1,
          message['type']?.toString() ?? 'int',
        );
      case 'cookie':
        return _handleCookie(Map<String, dynamic>.from(message));
      case 'uuid':
        return const Uuid().v1();
      case 'load_setting':
        return _loadSetting(message['key'], message['setting_key']);
      case 'isLogged':
        return _sources[message['key']]?.isLogged ?? false;
      case 'delay':
        return Future<void>.delayed(
          Duration(milliseconds: (message['time'] as int?) ?? 0),
        );
      case 'UI':
        return null;
      case 'getLocale':
        final locale = PlatformDispatcher.instance.locale;
        final countryCode = locale.countryCode ?? 'US';
        return '${locale.languageCode}_$countryCode';
      case 'getPlatform':
        return Platform.operatingSystem;
      case 'setClipboard':
        return Clipboard.setData(
          ClipboardData(text: message['text']?.toString() ?? ''),
        );
      case 'getClipboard':
        return Clipboard.getData(
          Clipboard.kTextPlain,
        ).then((data) => data?.text);
      case 'compute':
        final function = message['function'];
        final args = message['args'];
        if (function is! String) {
          throw StateError('compute function must be a string.');
        }
        return PluginJsPool.instance.execute(
          function,
          args is List ? List<dynamic>.from(args) : const <dynamic>[],
        );
    }

    return null;
  }

  Future<void> _saveSourceData(Map<dynamic, dynamic> message) async {
    final key = message['key']?.toString();
    final dataKey = message['data_key']?.toString();
    if (key == null || dataKey == null) {
      return;
    }
    final source = _sources[key];
    if (source == null) {
      return;
    }
    source.data[dataKey] = message['data'];
    await source.saveData();
  }

  Future<void> _deleteSourceData(Map<dynamic, dynamic> message) async {
    final key = message['key']?.toString();
    final dataKey = message['data_key']?.toString();
    if (key == null || dataKey == null) {
      return;
    }
    final source = _sources[key];
    if (source == null) {
      return;
    }
    source.data.remove(dataKey);
    await source.saveData();
  }

  dynamic _loadSetting(dynamic key, dynamic settingKey) {
    if (key is! String || settingKey is! String) {
      return null;
    }
    final source = _sources[key];
    if (source == null) {
      return null;
    }
    return source.data['settings']?[settingKey] ??
        source.settings[settingKey]?.defaultValue;
  }

  Future<Map<String, dynamic>> _handleHttp(Map<String, dynamic> request) async {
    Response<dynamic>? response;
    String? error;

    try {
      response = await _dio!.request(
        request['url'].toString(),
        data: request['data'],
        options: Options(
          method: request['http_method']?.toString() ?? 'GET',
          responseType: request['bytes'] == true
              ? ResponseType.bytes
              : ResponseType.plain,
          headers: Map<String, dynamic>.from(request['headers'] ?? {}),
          extra: Map<String, dynamic>.from(request['extra'] ?? {}),
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }

    final headers = <String, String>{};
    response?.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });

    var body = response?.data;
    if (body is List<int> && body is! Uint8List) {
      body = Uint8List.fromList(body);
    }

    return <String, dynamic>{
      'status': response?.statusCode,
      'headers': headers,
      'body': body,
      'error': error,
    };
  }

  Object? _handleCookie(Map<String, dynamic> message) {
    final url = message['url']?.toString();
    if (url == null) {
      return null;
    }
    final uri = Uri.parse(url);

    switch (message['function']) {
      case 'set':
        final cookies = <Cookie>[];
        for (final element
            in message['cookies'] as List? ?? const <dynamic>[]) {
          if (element is! Map) {
            continue;
          }
          final cookie = Cookie(
            element['name']?.toString() ?? '',
            element['value']?.toString() ?? '',
          );
          cookie.domain = element['domain']?.toString();
          cookies.add(cookie);
        }
        cookieStore.saveFromResponse(uri, cookies);
        return null;
      case 'get':
        return cookieStore.loadForRequest(uri).map((cookie) {
          return <String, dynamic>{
            'name': cookie.name,
            'value': cookie.value,
            'domain': cookie.domain,
            'path': cookie.path,
            'expires': cookie.expires?.millisecondsSinceEpoch,
            'secure': cookie.secure,
            'httpOnly': cookie.httpOnly,
          };
        }).toList();
      case 'delete':
        cookieStore.deleteForUri(uri);
        return null;
    }

    return null;
  }

  Object? _handleHtml(Map<String, dynamic> message) {
    switch (message['function']) {
      case 'parse':
        _documents[message['key'] as int] = _DocumentWrapper.parse(
          message['data'].toString(),
        );
        return null;
      case 'querySelector':
        return _documents[message['key']]?.querySelector(
          message['query'].toString(),
        );
      case 'querySelectorAll':
        return _documents[message['key']]?.querySelectorAll(
          message['query'].toString(),
        );
      case 'getText':
        return _documents[message['doc']]?.elementText(message['key'] as int);
      case 'getAttributes':
        return _documents[message['doc']]?.elementAttributes(
          message['key'] as int,
        );
      case 'dom_querySelector':
        return _documents[message['doc']]?.elementQuerySelector(
          message['key'] as int,
          message['query'].toString(),
        );
      case 'dom_querySelectorAll':
        return _documents[message['doc']]?.elementQuerySelectorAll(
          message['key'] as int,
          message['query'].toString(),
        );
      case 'getChildren':
        return _documents[message['doc']]?.elementChildren(
          message['key'] as int,
        );
      case 'getNodes':
        return _documents[message['doc']]?.elementNodes(message['key'] as int);
      case 'getInnerHTML':
        return _documents[message['doc']]?.elementInnerHtml(
          message['key'] as int,
        );
      case 'getParent':
        return _documents[message['doc']]?.elementParent(message['key'] as int);
      case 'node_text':
        return _documents[message['doc']]?.nodeText(message['key'] as int);
      case 'node_type':
        return _documents[message['doc']]?.nodeType(message['key'] as int);
      case 'node_toElement':
      case 'node_to_element':
        return _documents[message['doc']]?.nodeToElement(message['key'] as int);
      case 'dispose':
        _documents.remove(message['key']);
        return null;
      case 'getClassNames':
        return _documents[message['doc']]?.classNames(message['key'] as int);
      case 'getId':
        return _documents[message['doc']]?.elementId(message['key'] as int);
      case 'getLocalName':
        return _documents[message['doc']]?.localName(message['key'] as int);
      case 'getElementById':
        return _documents[message['key']]?.getElementById(
          message['id'].toString(),
        );
      case 'getPreviousSibling':
        return _documents[message['doc']]?.previousSibling(
          message['key'] as int,
        );
      case 'getNextSibling':
        return _documents[message['doc']]?.nextSibling(message['key'] as int);
    }
    return null;
  }

  Object? _handleConvert(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    final value = message['value'];
    final isEncode = message['isEncode'] == true;

    switch (type) {
      case 'utf8':
        return isEncode ? utf8.encode(value.toString()) : utf8.decode(value);
      case 'gbk':
        final codec = const GbkCodec();
        return isEncode
            ? Uint8List.fromList(codec.encode(value.toString()))
            : codec.decode(value);
      case 'base64':
        return isEncode ? base64Encode(value) : base64Decode(value.toString());
      case 'md5':
        return Uint8List.fromList(md5.convert(value).bytes);
      case 'sha1':
        return Uint8List.fromList(sha1.convert(value).bytes);
      case 'sha256':
        return Uint8List.fromList(sha256.convert(value).bytes);
      case 'sha512':
        return Uint8List.fromList(sha512.convert(value).bytes);
      case 'hmac':
        final digest = Hmac(switch (message['hash']) {
          'md5' => md5,
          'sha1' => sha1,
          'sha256' => sha256,
          'sha512' => sha512,
          _ => throw UnsupportedError('Unsupported HMAC algorithm'),
        }, message['key']);
        if (message['isString'] == true) {
          return digest.convert(value).toString();
        }
        return Uint8List.fromList(digest.convert(value).bytes);
      case 'aes-ecb':
        return _processBlockCipher(
          ECBBlockCipher(AESEngine()),
          value,
          isEncode,
          key: message['key'],
        );
      case 'aes-cbc':
        return _processBlockCipher(
          CBCBlockCipher(AESEngine()),
          value,
          isEncode,
          key: message['key'],
          iv: message['iv'],
        );
      case 'aes-cfb':
        return _processBlockCipher(
          CFBBlockCipher(AESEngine(), message['blockSize'] as int),
          value,
          isEncode,
          key: message['key'],
          iv: message['iv'],
        );
      case 'aes-ofb':
        return _processBlockCipher(
          OFBBlockCipher(AESEngine(), message['blockSize'] as int),
          value,
          isEncode,
          key: message['key'],
        );
      case 'rsa':
        if (isEncode) {
          return null;
        }
        final cipher = PKCS1Encoding(RSAEngine());
        cipher.init(
          false,
          PrivateKeyParameter<RSAPrivateKey>(
            _parsePrivateKey(message['key'] as String),
          ),
        );
        return _processInBlocks(cipher, value as Uint8List);
    }

    return value;
  }

  Uint8List _processBlockCipher(
    BlockCipher cipher,
    dynamic value,
    bool isEncode, {
    required dynamic key,
    dynamic iv,
  }) {
    final input = Uint8List.fromList(List<int>.from(value));
    final output = Uint8List(input.length);

    if (iv != null) {
      cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
    } else {
      cipher.init(isEncode, KeyParameter(key));
    }

    var offset = 0;
    while (offset < input.length) {
      offset += cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  RSAPrivateKey _parsePrivateKey(String key) {
    final privateKeyDer = base64Decode(key);
    var parser = ASN1Parser(privateKeyDer);
    final topLevelSeq = parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    parser = ASN1Parser(privateKey.valueBytes!);
    final pkSeq = parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      p.integer!,
      q.integer!,
    );
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher cipher, Uint8List input) {
    final numBlocks =
        input.length ~/ cipher.inputBlockSize +
        ((input.length % cipher.inputBlockSize != 0) ? 1 : 0);
    final output = Uint8List(numBlocks * cipher.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = inputOffset + cipher.inputBlockSize <= input.length
          ? cipher.inputBlockSize
          : input.length - inputOffset;
      outputOffset += cipher.processBlock(
        input,
        inputOffset,
        chunkSize,
        output,
        outputOffset,
      );
      inputOffset += chunkSize;
    }

    return output.sublist(0, outputOffset);
  }

  num _random(num min, num max, String type) {
    if (type == 'double') {
      return min + (max - min) * math.Random().nextDouble();
    }
    return (min + (max - min) * math.Random().nextDouble()).toInt();
  }
}

class _DocumentWrapper {
  _DocumentWrapper.parse(String content)
    : document = html_parser.parse(content);

  final html.Document document;
  final List<html.Element> _elements = [];
  final List<html.Node> _nodes = [];

  int? querySelector(String query) {
    final element = document.querySelector(query);
    if (element == null) {
      return null;
    }
    _elements.add(element);
    return _elements.length - 1;
  }

  List<int> querySelectorAll(String query) {
    final elements = document.querySelectorAll(query);
    final keys = <int>[];
    for (final element in elements) {
      _elements.add(element);
      keys.add(_elements.length - 1);
    }
    return keys;
  }

  String? elementText(int key) => _elements[key].text;

  Map<String, String> elementAttributes(int key) {
    return Map<String, String>.from(_elements[key].attributes);
  }

  int? elementQuerySelector(int key, String query) {
    final element = _elements[key].querySelector(query);
    if (element == null) {
      return null;
    }
    _elements.add(element);
    return _elements.length - 1;
  }

  List<int> elementQuerySelectorAll(int key, String query) {
    final elements = _elements[key].querySelectorAll(query);
    final keys = <int>[];
    for (final element in elements) {
      _elements.add(element);
      keys.add(_elements.length - 1);
    }
    return keys;
  }

  List<int> elementChildren(int key) {
    final keys = <int>[];
    for (final child in _elements[key].children) {
      _elements.add(child);
      keys.add(_elements.length - 1);
    }
    return keys;
  }

  List<int> elementNodes(int key) {
    final keys = <int>[];
    for (final node in _elements[key].nodes) {
      _nodes.add(node);
      keys.add(_nodes.length - 1);
    }
    return keys;
  }

  String? elementInnerHtml(int key) => _elements[key].innerHtml;

  int? elementParent(int key) {
    final parent = _elements[key].parent;
    if (parent == null) {
      return null;
    }
    _elements.add(parent);
    return _elements.length - 1;
  }

  String? nodeText(int key) => _nodes[key].text;

  String nodeType(int key) {
    return switch (_nodes[key].nodeType) {
      html.Node.ELEMENT_NODE => 'element',
      html.Node.TEXT_NODE => 'text',
      html.Node.COMMENT_NODE => 'comment',
      html.Node.DOCUMENT_NODE => 'document',
      _ => 'unknown',
    };
  }

  int? nodeToElement(int key) {
    final node = _nodes[key];
    if (node is! html.Element) {
      return null;
    }
    _elements.add(node);
    return _elements.length - 1;
  }

  List<String> classNames(int key) => _elements[key].classes.toList();

  String? elementId(int key) => _elements[key].id;

  String? localName(int key) => _elements[key].localName;

  int? getElementById(String id) {
    final element = document.getElementById(id);
    if (element == null) {
      return null;
    }
    _elements.add(element);
    return _elements.length - 1;
  }

  int? previousSibling(int key) {
    final sibling = _elements[key].previousElementSibling;
    if (sibling == null) {
      return null;
    }
    _elements.add(sibling);
    return _elements.length - 1;
  }

  int? nextSibling(int key) {
    final sibling = _elements[key].nextElementSibling;
    if (sibling == null) {
      return null;
    }
    _elements.add(sibling);
    return _elements.length - 1;
  }
}
