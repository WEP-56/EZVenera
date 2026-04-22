import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/state/app_state_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await AppStateController.instance.initialize();
  }
  runApp(const EZVeneraApp());
  if (Platform.isWindows) {
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setMinimumSize(const Size(720, 560));
      final windowState = AppStateController.instance.getSection(
        'window.bounds',
      );
      final width = (windowState['width'] as num?)?.toDouble();
      final height = (windowState['height'] as num?)?.toDouble();
      if (width != null && height != null && width >= 720 && height >= 560) {
        await windowManager.setSize(Size(width, height));
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
