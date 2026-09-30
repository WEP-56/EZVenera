import 'dart:async';

/// One named teardown action executed by [AppShutdown].
class ShutdownStep {
  const ShutdownStep({required this.name, required this.run});

  final String name;
  final Future<void> Function() run;
}

/// Outcome of a single [ShutdownStep].
class ShutdownStepResult {
  const ShutdownStepResult({
    required this.name,
    this.error,
    this.timedOut = false,
  });

  final String name;
  final Object? error;
  final bool timedOut;

  bool get isClean => error == null && !timedOut;
}

/// Closes every live subsystem in [steps] order, at most once.
///
/// The Windows runner destroys the Flutter engine the moment the window dies.
/// If native code still owns live work at that point — QuickJS mid-`evaluate`
/// in a pool isolate, the rhttp Rust runtime, WebView2 COM threads — the VM
/// teardown aborts the process instead of exiting, which Windows reports as a
/// fast-fail (0xC0000409: "the exception handler will not be called and the
/// process will terminate immediately"). Every exit path must therefore [run]
/// before closing the window.
///
/// Steps are isolated: a throwing or hung step is recorded and the following
/// steps still execute, so cleanup can never be the reason the app fails to
/// quit. A step whose future never settles is given up on after [stepTimeout];
/// the underlying work is not cancelled, it is simply no longer waited for.
class AppShutdown {
  AppShutdown({
    required this.steps,
    this.stepTimeout = const Duration(seconds: 3),
  });

  final List<ShutdownStep> steps;
  final Duration stepTimeout;

  Future<List<ShutdownStepResult>>? _runFuture;

  bool get hasRun => _runFuture != null;

  Future<List<ShutdownStepResult>> run({
    void Function(ShutdownStepResult result)? onStepResult,
  }) {
    return _runFuture ??= _runAll(onStepResult);
  }

  Future<List<ShutdownStepResult>> _runAll(
    void Function(ShutdownStepResult result)? onStepResult,
  ) async {
    final results = <ShutdownStepResult>[];
    for (final step in steps) {
      final result = await _runStep(step);
      results.add(result);
      onStepResult?.call(result);
    }
    return results;
  }

  Future<ShutdownStepResult> _runStep(ShutdownStep step) async {
    try {
      await step.run().timeout(stepTimeout);
      return ShutdownStepResult(name: step.name);
    } on TimeoutException {
      return ShutdownStepResult(name: step.name, timedOut: true);
    } catch (error) {
      return ShutdownStepResult(name: step.name, error: error);
    }
  }
}
