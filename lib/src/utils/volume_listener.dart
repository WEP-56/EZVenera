import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Android hardware volume-key events to Dart code.
///
/// Listens to the `ezvenera/volume` [EventChannel] exposed by the native
/// host activity. Events are integer codes:
///
/// * `1` - volume up pressed.
/// * `2` - volume down pressed.
///
/// While at least one listener is active the keys are consumed by the
/// activity (so the system media volume does not change); once the reader
/// page disposes the subscription, the keys fall back to the default
/// behavior.
class VolumeListener {
  VolumeListener({this.onUp, this.onDown});

  /// Called when the hardware volume-up button is pressed.
  final VoidCallback? onUp;

  /// Called when the hardware volume-down button is pressed.
  final VoidCallback? onDown;

  static const _channel = EventChannel('ezvenera/volume');

  StreamSubscription<dynamic>? _subscription;

  /// True only on platforms where the native counterpart is wired up.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Starts listening. Safe to call multiple times - duplicate calls are
  /// ignored while the existing subscription is still active.
  void listen() {
    if (!isSupported || _subscription != null) {
      return;
    }
    _subscription = _channel.receiveBroadcastStream().listen(_onEvent);
  }

  /// Stops listening and releases the native side so volume keys resume
  /// their system behavior.
  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onEvent(dynamic event) {
    if (event == 1) {
      onUp?.call();
    } else if (event == 2) {
      onDown?.call();
    }
  }
}
