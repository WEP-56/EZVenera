import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

class PluginJsPool {
  PluginJsPool._();

  static final PluginJsPool instance = PluginJsPool._();
  static const _maxInstances = 4;

  final List<_IsolateJsEngine> _instances = [];
  bool _isInitializing = false;

  Future<void> ensureInitialized() async {
    if (_instances.isNotEmpty || _isInitializing) {
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return;
    }

    _isInitializing = true;
    final buffer = await rootBundle.load('assets/init.js');
    final jsInit = buffer.buffer.asUint8List();
    for (var index = 0; index < _maxInstances; index++) {
      _instances.add(_IsolateJsEngine(jsInit));
    }
    _isInitializing = false;
  }

  Future<dynamic> execute(String jsFunction, List<dynamic> args) async {
    await ensureInitialized();
    var selected = _instances.first;
    for (final instance in _instances) {
      if (instance.pendingTasks < selected.pendingTasks) {
        selected = instance;
      }
    }
    return selected.execute(jsFunction, args);
  }
}

class _IsolateJsEngineInitParams {
  const _IsolateJsEngineInitParams(this.sendPort, this.jsInit);

  final SendPort sendPort;
  final Uint8List jsInit;
}

class _IsolateJsEngine {
  _IsolateJsEngine(this.jsInit) {
    _receivePort = ReceivePort();
    _receivePort!.listen(_onMessage);
    Isolate.spawn(
      _run,
      _IsolateJsEngineInitParams(_receivePort!.sendPort, jsInit),
    );
  }

  final Uint8List jsInit;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  int _counter = 0;
  final Map<int, Completer<dynamic>> _tasks = {};

  int get pendingTasks => _tasks.length;

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      return;
    }

    if (message is _TaskResult) {
      final completer = _tasks.remove(message.id);
      if (completer == null) {
        return;
      }
      if (message.error != null) {
        completer.completeError(message.error!);
      } else {
        completer.complete(message.result);
      }
    }
  }

  static Future<void> _run(_IsolateJsEngineInitParams params) async {
    final port = ReceivePort();
    params.sendPort.send(port.sendPort);

    final engine = FlutterQjs()..dispatch();
    final setGlobal = engine.evaluate('(key, value) => { this[key] = value; }');
    (setGlobal as JSInvokable)(['sendMessage', (_) => null]);
    setGlobal.free();
    engine.evaluate(String.fromCharCodes(params.jsInit), name: '<init>');

    await for (final message in port) {
      if (message is! _Task) {
        continue;
      }

      try {
        final jsFunc = engine.evaluate(message.jsFunction);
        if (jsFunc is! JSInvokable) {
          throw StateError(
            'The provided code does not evaluate to a function.',
          );
        }
        final result = jsFunc.invoke(message.args);
        jsFunc.free();
        params.sendPort.send(_TaskResult(message.id, result, null));
      } catch (error) {
        params.sendPort.send(_TaskResult(message.id, null, error.toString()));
      }
    }
  }

  Future<dynamic> execute(String jsFunction, List<dynamic> args) async {
    while (_sendPort == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final taskId = _counter++;
    final completer = Completer<dynamic>();
    _tasks[taskId] = completer;
    _sendPort!.send(_Task(taskId, jsFunction, args));
    return completer.future;
  }
}

class _Task {
  const _Task(this.id, this.jsFunction, this.args);

  final int id;
  final String jsFunction;
  final List<dynamic> args;
}

class _TaskResult {
  const _TaskResult(this.id, this.result, this.error);

  final int id;
  final Object? result;
  final String? error;
}
