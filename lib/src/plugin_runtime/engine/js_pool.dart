import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

class PluginJsPool {
  PluginJsPool._();

  static final PluginJsPool instance = PluginJsPool._();
  static const _maxInstances = 4;

  final List<_IsolateJsEngine> _instances = [];
  bool _shutdown = false;

  /// Cached initialization future: concurrent callers await the same
  /// initialization instead of polling a flag. A failure clears the cache
  /// so the next call retries instead of hanging forever.
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    if (_shutdown) {
      return Future<void>.error(
        StateError('PluginJsPool is shut down; refusing to spawn engines.'),
      );
    }
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final buffer = await rootBundle.load('assets/init.js');
      final jsInit = buffer.buffer.asUint8List();
      for (var index = 0; index < _maxInstances; index++) {
        _instances.add(await _IsolateJsEngine.create(jsInit));
      }
    } on Object {
      // Drop partially spawned engines so a retry cannot accumulate instances
      // beyond the pool capacity; the spawned isolates leak until process
      // exit, which is acceptable for a failure path this rare.
      _instances.clear();
      // Reset so a later call can retry; the error still propagates to the
      // caller that triggered this initialization.
      _initFuture = null;
      rethrow;
    }
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

  /// Asks every engine isolate to finish its queued tasks and exit on its own,
  /// so no QuickJS call is still on the stack when the window is destroyed.
  /// An isolate that outlives [grace] is killed as a last resort.
  Future<void> shutdown({Duration grace = const Duration(seconds: 2)}) async {
    if (_shutdown) {
      return;
    }
    _shutdown = true;
    final instances = List<_IsolateJsEngine>.of(_instances);
    _instances.clear();
    _initFuture = null;
    await Future.wait(instances.map((engine) => engine.shutdown(grace)));
  }
}

class _IsolateJsEngineInitParams {
  const _IsolateJsEngineInitParams(this.sendPort, this.jsInit);

  final SendPort sendPort;
  final Uint8List jsInit;
}

class _IsolateJsEngine {
  _IsolateJsEngine._(this.jsInit) {
    _receivePort = ReceivePort();
    _receivePort!.listen(_onMessage);
    _spawnFuture =
        Isolate.spawn(
          _run,
          _IsolateJsEngineInitParams(_receivePort!.sendPort, jsInit),
        ).then((isolate) {
          _isolate = isolate;
        });
  }

  /// Creates the engine and surfaces spawn failures at pool initialization
  /// time — the spawn future used to be discarded, so a failed spawn left an
  /// engine whose dead isolate would never answer its tasks.
  static Future<_IsolateJsEngine> create(Uint8List jsInit) async {
    final engine = _IsolateJsEngine._(jsInit);
    await engine._spawnFuture;
    return engine;
  }

  final Uint8List jsInit;
  late final Future<void> _spawnFuture;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Isolate? _isolate;
  int _counter = 0;
  final Map<int, Completer<dynamic>> _tasks = {};
  final Completer<void> _exited = Completer<void>();

  int get pendingTasks => _tasks.length;

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      return;
    }

    if (message is _ShutdownAck) {
      if (!_exited.isCompleted) {
        _exited.complete();
      }
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

  /// Completes once the child isolate has drained its queue and returned.
  Future<void> shutdown(Duration grace) async {
    final sendPort = _sendPort;
    final isolate = _isolate;
    if (sendPort == null || isolate == null) {
      // Handshake never finished, so the isolate cannot be holding a task.
      _kill();
      _closePort();
      return;
    }

    sendPort.send(const _Shutdown());
    await _exited.future.timeout(grace, onTimeout: _kill);
    _closePort();
  }

  void _kill() {
    try {
      // beforeNextEvent, not immediate: interrupting QuickJS mid-call is the
      // abort this whole shutdown path exists to avoid.
      _isolate?.kill(priority: Isolate.beforeNextEvent);
    } catch (_) {
      // Already terminated.
    }
  }

  void _closePort() {
    _receivePort?.close();
    _receivePort = null;
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
      if (message is _Shutdown) {
        break;
      }
      if (message is! _Task) {
        continue;
      }

      JSInvokable? jsFunc;
      try {
        final evaluated = engine.evaluate(message.jsFunction);
        if (evaluated is! JSInvokable) {
          throw StateError(
            'The provided code does not evaluate to a function.',
          );
        }
        jsFunc = evaluated;
        final result = jsFunc.invoke(message.args);
        params.sendPort.send(_TaskResult(message.id, result, null));
      } catch (error) {
        params.sendPort.send(_TaskResult(message.id, null, error.toString()));
      } finally {
        // The native JSInvokable handle must be released even when invoke
        // throws, otherwise repeated plugin errors leak QuickJS memory.
        jsFunc?.free();
      }
    }

    // Stop the JS event loop and let the isolate return by itself; the
    // shutdown ack is sent last so the parent only stops waiting once this
    // isolate is provably out of native code.
    engine.port.close();
    params.sendPort.send(const _ShutdownAck());
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

/// Parent -> isolate: answer the tasks you already have, then return.
class _Shutdown {
  const _Shutdown();
}

/// Isolate -> parent: this isolate is out of native code and about to exit.
class _ShutdownAck {
  const _ShutdownAck();
}
