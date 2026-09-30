import 'dart:async';

import 'package:window_manager/window_manager.dart';

import '../backup/webdav_auto_sync.dart';
import '../lifecycle/app_shutdown.dart';
import '../logging/app_logger.dart';
import '../network/network_client_factory.dart';
import '../pages/plugin_webview_login_page.dart';
import '../plugin_runtime/engine/js_pool.dart';
import '../plugin_runtime/plugin_runtime.dart';
import '../settings/settings_controller.dart';
import '../state/app_state_controller.dart';

/// The single exit path on Windows.
///
/// Closing the window used to tear the Dart VM down while the plugin JS
/// isolates, the rhttp (Rust) WebDAV runtime and the WebView2 environment were
/// still live; Windows reports such an aborted teardown as a fast-fail
/// (0xC0000409, "the exception handler will not be called and the process will
/// terminate immediately"). [install] therefore claims the native close
/// message, drains everything that can still reach into native code, and only
/// then lets the runner return from `wWinMain`, which is where the Flutter
/// engine gets its orderly shutdown.
class WindowsExitHandler with WindowListener {
  WindowsExitHandler._();

  static final WindowsExitHandler instance = WindowsExitHandler._();

  /// Long enough for a stalled WebDAV/JS task to notice, short enough that a
  /// hung subsystem cannot freeze the window on its way out.
  ///
  /// Must stay strictly above every deadline a step imposes on itself: the
  /// outer [AppShutdown] timer and an inner timer of equal length race, and the
  /// outer one always wins because it starts first. When that happens the step
  /// is abandoned as "did not drain in time" before the inner handler can run
  /// its own last resort, and the runner is torn down with that work still
  /// live - the exact condition this class exists to prevent.
  static const Duration stepTimeout = Duration(seconds: 5);

  /// How long an engine isolate may take to drain its queue and exit on its
  /// own before the pool kills it. Kept below [stepTimeout] so the kill is
  /// always requested before the step is given up on.
  static const Duration jsPoolGrace = Duration(seconds: 2);

  bool _exitRequested = false;

  final AppShutdown _shutdown = AppShutdown(
    stepTimeout: stepTimeout,
    steps: [
      // Producers first: nothing below may gain new in-flight work halfway
      // through the drain.
      ShutdownStep(name: 'webdav-auto-sync', run: WebDavAutoSync.instance.stop),
      ShutdownStep(
        name: 'plugin-js-pool',
        run: () => PluginJsPool.instance.shutdown(grace: jsPoolGrace),
      ),
      ShutdownStep(
        name: 'plugin-runtime',
        run: PluginRuntime.instance.shutdown,
      ),
      ShutdownStep(
        name: 'network',
        run: NetworkClientFactory.instance.shutdown,
      ),
      ShutdownStep(
        name: 'webview-environment',
        run: PluginWebviewLoginPage.disposeEnvironment,
      ),
      ShutdownStep(name: 'flush-settings', run: _flushSettings),
      ShutdownStep(name: 'app-log', run: AppLogger.instance.flush),
    ],
  );

  static Future<void> _flushSettings() async {
    await SettingsController.instance.flush();
    await AppStateController.instance.flush();
  }

  /// Starts intercepting the native close message. Call once, on Windows,
  /// after `windowManager.ensureInitialized()`.
  Future<void> install() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() {
    unawaited(requestExit());
  }

  /// Drains the subsystems and quits the app. Safe to call from anywhere
  /// (title-bar X, Alt+F4, the updater handing off to the installer); only the
  /// first call does anything.
  Future<void> requestExit() async {
    if (_exitRequested) {
      return;
    }
    _exitRequested = true;

    unawaited(
      AppLogger.instance.info('[exit] close requested; draining subsystems'),
    );
    // Get the window out of the way first: a drain that waits on the network
    // would otherwise leave a frozen window on screen.
    await _hideWindow();

    try {
      final results = await _shutdown.run(onStepResult: _logStep);
      final stuck = results.where((result) => !result.isClean).toList();
      await AppLogger.instance.info(
        stuck.isEmpty
            ? '[exit] subsystems drained; quitting'
            : '[exit] quitting with undrained subsystems: ${_describe(stuck)}',
      );
      await AppLogger.instance.flush();
    } finally {
      if (!await _quitRunner()) {
        await _rearmForRetry();
      }
    }
  }

  static String _describe(List<ShutdownStepResult> results) {
    return results
        .map((result) {
          final why = result.timedOut ? 'timeout' : 'error: ${result.error}';
          return '${result.name} ($why)';
        })
        .join(', ');
  }

  void _logStep(ShutdownStepResult result) {
    if (result.isClean) {
      unawaited(AppLogger.instance.info('[exit] ${result.name} drained'));
      return;
    }
    if (result.timedOut) {
      unawaited(
        AppLogger.instance.warning(
          '[exit] ${result.name} did not drain in time',
        ),
      );
      return;
    }
    unawaited(
      AppLogger.instance.error('[exit] ${result.name} failed', result.error),
    );
  }

  Future<void> _hideWindow() async {
    try {
      await windowManager.hide();
    } catch (_) {
      // Cosmetic only; a window that will not hide must not block the exit.
    }
  }

  Future<bool> _quitRunner() async {
    try {
      await windowManager.destroy();
      return true;
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          '[exit] windowManager.destroy() failed',
          error,
          stackTrace,
        ),
      );
      return false;
    }
  }

  /// Last resort when the runner refuses to quit. The window is hidden and
  /// `preventClose` is still armed, so leaving it that way means every later
  /// close attempt hits the `_exitRequested` latch and the user is left with a
  /// live, invisible process that only Task Manager can stop - with the network
  /// layer, the JS pool and the cookie database already torn down. Give the
  /// window back and disarm the intercept: the next close goes through the
  /// native path.
  Future<void> _rearmForRetry() async {
    _exitRequested = false;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.show();
      await AppLogger.instance.warning(
        '[exit] runner refused to quit; window restored, close again to force exit',
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          '[exit] could not restore the window after a failed quit',
          error,
          stackTrace,
        ),
      );
    }
  }
}
