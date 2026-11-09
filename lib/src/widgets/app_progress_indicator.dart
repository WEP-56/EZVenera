import 'package:flutter/material.dart';

import '../settings/settings_controller.dart';

/// Progress indicator that stays still in E-Ink mode (REQ-002).
///
/// The indeterminate [CircularProgressIndicator] drives an endlessly repeating
/// [AnimationController]; on a 1-bit panel that is a permanent stream of
/// partial refreshes and ghosting while anything loads. In E-Ink mode this
/// widget pins the indicator to a fixed arc (no ticking at all); elsewhere it
/// behaves exactly like the default indicator.
///
/// Subscribes to [SettingsController] itself so the static/animated choice is
/// correct even when embedded in a `const` subtree that an ancestor rebuild
/// would otherwise skip.
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({super.key, this.strokeWidth = 4.0});

  /// Mirrors [CircularProgressIndicator.strokeWidth].
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsController.instance,
      builder: (context, _) {
        final eink = SettingsController.instance.einkMode;
        return CircularProgressIndicator(
          strokeWidth: strokeWidth,
          // A determinate value stops the internal controller (the SDK only
          // repeats while value == null); the fixed arc reads as "loading"
          // without generating a single refresh cycle.
          value: eink ? 0.30 : null,
        );
      },
    );
  }
}
