import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:lodepng_flutter/lodepng_flutter.dart' as lodepng;

class PluginImageModifier {
  PluginImageModifier._();

  static final PluginImageModifier instance = PluginImageModifier._();

  FlutterQjs? _engine;
  Future<void>? _initializeFuture;
  final Map<int, _RuntimeImage> _images = <int, _RuntimeImage>{};
  int _nextImageKey = 1;
  Future<void> _queue = Future<void>.value();

  Future<Uint8List> apply(Uint8List bytes, String script) async {
    if (!script.contains('modifyImage')) {
      return bytes;
    }
    final completer = Completer<Uint8List>();
    _queue = _queue
        .then((_) async {
          try {
            completer.complete(await _applyInternal(bytes, script));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((_) {});
    return completer.future;
  }

  Future<Uint8List> _applyInternal(Uint8List bytes, String script) async {
    try {
      await _ensureInitialized();
      final image = await _RuntimeImage.decode(bytes);
      _images.clear();
      final imageKey = _setImage(image);

      final resultKey = _engine!.evaluate('''
        (() => {
          $script
          let image = new Image($imageKey);
          let result = typeof modifyImage === 'function' ? modifyImage(image) : null;
          return result ? result.key : null;
        })()
      ''', name: '<modify_image_exec>');

      if (resultKey is! num) {
        return bytes;
      }

      final modified = _images[resultKey.toInt()];
      if (modified == null) {
        return bytes;
      }
      return modified.encodePng();
    } catch (_) {
      return bytes;
    } finally {
      _images.clear();
    }
  }

  Future<void> _ensureInitialized() {
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    _engine = FlutterQjs()..dispatch();
    final setGlobal = _engine!.evaluate(
      '(key, value) => { this[key] = value; }',
    );
    (setGlobal as JSInvokable)(['sendMessage', _onMessage]);
    setGlobal(['appVersion', '0.1.0']);
    setGlobal.free();

    final initJs = await rootBundle.loadString('assets/init.js');
    _engine!.evaluate(initJs, name: '<init>');
  }

  dynamic _onMessage(dynamic message) {
    if (message is! Map<dynamic, dynamic>) {
      return null;
    }
    if (message['method']?.toString() != 'image') {
      return null;
    }

    switch (message['function']?.toString()) {
      case 'copyRange':
        return _copyRange(message);
      case 'copyAndRotate90':
        return _copyAndRotate90(message);
      case 'fillImageAt':
        return _fillImageAt(message);
      case 'fillImageRangeAt':
        return _fillImageRangeAt(message);
      case 'getWidth':
        return _images[_key(message)]?.width;
      case 'getHeight':
        return _images[_key(message)]?.height;
      case 'emptyImage':
        return _emptyImage(message);
    }
    return null;
  }

  int? _copyRange(Map<dynamic, dynamic> message) {
    final image = _images[_key(message)];
    if (image == null) {
      return null;
    }
    return _setImage(
      image.copyRange(
        _intValue(message['x']),
        _intValue(message['y']),
        _intValue(message['width']),
        _intValue(message['height']),
      ),
    );
  }

  int? _copyAndRotate90(Map<dynamic, dynamic> message) {
    final image = _images[_key(message)];
    if (image == null) {
      return null;
    }
    return _setImage(image.copyAndRotate90());
  }

  dynamic _fillImageAt(Map<dynamic, dynamic> message) {
    final target = _images[_key(message)];
    final source = _images[_intValue(message['image'])];
    if (target == null || source == null) {
      return null;
    }
    target.fillImageAt(
      _intValue(message['x']),
      _intValue(message['y']),
      source,
    );
    return null;
  }

  dynamic _fillImageRangeAt(Map<dynamic, dynamic> message) {
    final target = _images[_key(message)];
    final source = _images[_intValue(message['image'])];
    if (target == null || source == null) {
      return null;
    }
    target.fillImageRangeAt(
      _intValue(message['x']),
      _intValue(message['y']),
      source,
      _intValue(message['srcX']),
      _intValue(message['srcY']),
      _intValue(message['width']),
      _intValue(message['height']),
    );
    return null;
  }

  int _emptyImage(Map<dynamic, dynamic> message) {
    return _setImage(
      _RuntimeImage.empty(
        _intValue(message['width']),
        _intValue(message['height']),
      ),
    );
  }

  int _setImage(_RuntimeImage image) {
    final key = _nextImageKey++;
    _images[key] = image;
    return key;
  }

  int _key(Map<dynamic, dynamic> message) => _intValue(message['key']);

  int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.parse(value.toString());
  }
}

class _RuntimeImage {
  _RuntimeImage(this._data, this.width, this.height) {
    if (_data.length != width * height) {
      throw ArgumentError('Invalid image data size.');
    }
  }

  _RuntimeImage.empty(this.width, this.height)
    : _data = Uint32List(width * height);

  final Uint32List _data;
  final int width;
  final int height;

  static Future<_RuntimeImage> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final width = frame.image.width;
    final height = frame.image.height;
    final raw = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    frame.image.dispose();
    if (raw == null) {
      throw StateError('Failed to decode image.');
    }
    return _RuntimeImage(raw.buffer.asUint32List(), width, height);
  }

  _RuntimeImage copyRange(int x, int y, int width, int height) {
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[j * width + i] = _data[(j + y) * this.width + i + x];
      }
    }
    return _RuntimeImage(data, width, height);
  }

  void fillImageAt(int x, int y, _RuntimeImage image) {
    for (var j = 0; j < image.height && (j + y) < height; j++) {
      for (var i = 0; i < image.width && (i + x) < width; i++) {
        _data[(j + y) * width + i + x] = image._data[j * image.width + i];
      }
    }
  }

  void fillImageRangeAt(
    int x,
    int y,
    _RuntimeImage image,
    int srcX,
    int srcY,
    int width,
    int height,
  ) {
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        _data[(j + y) * this.width + i + x] =
            image._data[(j + srcY) * image.width + i + srcX];
      }
    }
  }

  _RuntimeImage copyAndRotate90() {
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[i * height + height - j - 1] = _data[j * width + i];
      }
    }
    return _RuntimeImage(data, height, width);
  }

  Uint8List encodePng() {
    final data = lodepng.encodePngToPointer(
      lodepng.Image(_data.buffer.asUint8List(), width, height),
    );
    return Pointer<Uint8>.fromAddress(
      data.address,
    ).asTypedList(data.length, finalizer: lodepng.ByteBuffer.finalizer);
  }
}
