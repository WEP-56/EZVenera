import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/app.dart';
import 'package:ezvenera/src/settings/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('ezv_eink_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => supportDir.path,
        );
    await SettingsController.instance.initialize();
  });

  tearDownAll(() async {
    await supportDir.delete(recursive: true);
  });

  group('SettingsController E-Ink settings (REQ-001)', () {
    test('defaults are off with high contrast and refresh hint enabled', () {
      final controller = SettingsController.instance;
      // Ensure a clean baseline even if other tests flipped the mode.
      return controller.reset().then((_) {
        expect(controller.einkMode, isFalse);
        expect(controller.einkHighContrast, isTrue);
        expect(controller.einkFullRefreshHint, isTrue);
      });
    });

    test('eink settings persist to disk and round-trip through backup',
        () async {
      final controller = SettingsController.instance;
      await controller.setEinkMode(true);
      await controller.setEinkHighContrast(false);
      await controller.setEinkFullRefreshHint(false);

      final file = File('${supportDir.path}/settings/app_settings.json');
      final onDisk =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(onDisk['einkMode'], isTrue);
      expect(onDisk['einkHighContrast'], isFalse);
      expect(onDisk['einkFullRefreshHint'], isFalse);

      final backup = controller.toBackupJson();
      expect(backup['einkMode'], isTrue);
      expect(backup['einkHighContrast'], isFalse);
      expect(backup['einkFullRefreshHint'], isFalse);

      // Restore flips them back through the same code path used by
      // .ezvenera imports and WebDAV sync.
      await controller.restoreFromBackupJson(<String, dynamic>{
        'einkMode': false,
      });
      expect(controller.einkMode, isFalse);
      // Absent keys keep their defaults (backwards compatibility, NFR-003).
      expect(controller.einkHighContrast, isTrue);
      expect(controller.einkFullRefreshHint, isTrue);

      await controller.reset();
    });

    test('reset restores E-Ink defaults', () async {
      final controller = SettingsController.instance;
      await controller.setEinkMode(true);
      await controller.setEinkHighContrast(false);
      await controller.reset();
      expect(controller.einkMode, isFalse);
      expect(controller.einkHighContrast, isTrue);
      expect(controller.einkFullRefreshHint, isTrue);
    });
  });

  group('buildEinkThemeData (REQ-003)', () {
    test('light variant is pure white background with black foreground', () {
      final theme = buildEinkThemeData(Brightness.light);
      expect(theme.scaffoldBackgroundColor, Colors.white);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.primary, Colors.black);
      expect(theme.colorScheme.onSurface, Colors.black);
    });

    test('dark variant is pure black background with white foreground', () {
      final theme = buildEinkThemeData(Brightness.dark);
      expect(theme.scaffoldBackgroundColor, Colors.black);
      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.colorScheme.primary, Colors.white);
      expect(theme.colorScheme.onSurface, Colors.white);
    });

    test('no gray surface tones leak through', () {
      for (final brightness in Brightness.values) {
        final theme = buildEinkThemeData(brightness);
        final background = brightness == Brightness.dark
            ? Colors.black
            : Colors.white;
        final foreground = brightness == Brightness.dark
            ? Colors.white
            : Colors.black;
        expect(theme.colorScheme.surfaceContainerHighest, background);
        expect(theme.colorScheme.surfaceContainerHigh, background);
        expect(theme.colorScheme.surfaceContainer, background);
        expect(theme.colorScheme.surfaceContainerLow, background);
        expect(theme.colorScheme.surfaceContainerLowest, background);
        // Borders and tinted containers must be opaque: low-alpha ink
        // thresholds into invisible dithered noise on 1-bit panels.
        expect(theme.colorScheme.outline, foreground);
        expect(theme.colorScheme.outlineVariant, foreground);
        expect(theme.colorScheme.primaryContainer, background);
        expect(theme.colorScheme.onPrimaryContainer, foreground);
        expect(theme.colorScheme.secondaryContainer, background);
        expect(theme.colorScheme.onSecondaryContainer, foreground);
        expect(theme.colorScheme.tertiaryContainer, background);
        expect(theme.colorScheme.onTertiaryContainer, foreground);
      }
    });
  });

  group('applyEinkMotion (REQ-002)', () {
    test('disables ink splashes and page transitions', () {
      final theme = applyEinkMotion(ThemeData(useMaterial3: true));
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.splashColor, Colors.transparent);
      expect(theme.highlightColor, Colors.transparent);
      expect(theme.hoverColor, Colors.transparent);
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<EinkNoPageTransitionsBuilder>(),
      );
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.windows],
        isA<EinkNoPageTransitionsBuilder>(),
      );
    });

    test('high-contrast theme ships with the motion gating applied', () {
      // The app applies applyEinkMotion on top of buildEinkThemeData whenever
      // E-Ink mode is on; assert the composition end state.
      final theme = applyEinkMotion(buildEinkThemeData(Brightness.light));
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.colorScheme.outline, Colors.black);
    });
  });
}
