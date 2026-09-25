import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bootstrap/app_bootstrap.dart';
import 'localization/app_localizations.dart';
import 'settings/settings_controller.dart';
import 'shell/windows_window_frame.dart';

class EZVeneraApp extends StatefulWidget {
  const EZVeneraApp({super.key});

  @override
  State<EZVeneraApp> createState() => _EZVeneraAppState();
}

class _EZVeneraAppState extends State<EZVeneraApp> {
  final settings = SettingsController.instance;

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EZVenera',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        return _SystemUiProvider(
          child: WindowsWindowFrame(child: child ?? const SizedBox.shrink()),
        );
      },
      theme: settings.einkMode && settings.einkHighContrast
          ? buildEinkThemeData(Brightness.light)
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: settings.themeSeedColor,
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xFFF7F4EC),
              useMaterial3: true,
            ),
      darkTheme: settings.einkMode && settings.einkHighContrast
          ? buildEinkThemeData(Brightness.dark)
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: settings.themeSeedColor,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
      home: const AppBootstrap(),
    );
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

/// Pure black/white Material theme for E-Ink screens (REQ-003).
///
/// Every surface tone collapses to the background color so panels rely on
/// borders instead of subtle surface tinting (which E-Ink renders as muddy
/// gray). Public so it can be asserted directly in widget tests.
ThemeData buildEinkThemeData(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final background = isDark ? Colors.black : Colors.white;
  final foreground = isDark ? Colors.white : Colors.black;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: foreground,
    onPrimary: background,
    secondary: foreground,
    onSecondary: background,
    tertiary: foreground,
    onTertiary: background,
    error: foreground,
    onError: background,
    surface: background,
    onSurface: foreground,
    onSurfaceVariant: foreground,
    outline: foreground.withValues(alpha: 0.6),
    outlineVariant: foreground.withValues(alpha: 0.25),
    surfaceContainerHighest: background,
    surfaceContainerHigh: background,
    surfaceContainer: background,
    surfaceContainerLow: background,
    surfaceContainerLowest: background,
    surfaceDim: background,
    surfaceBright: background,
    surfaceTint: Colors.transparent,
    inverseSurface: foreground,
    onInverseSurface: background,
    inversePrimary: background,
    shadow: foreground,
    scrim: foreground,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    useMaterial3: true,
  );
}

/// Keeps status/navigation bars transparent and disables the system nav-bar
/// contrast scrim (white/translucent bar on some OEMs) after Flutter starts.
///
/// Splash-phase styling is handled by LaunchTheme/NormalTheme in Android
/// styles.xml — SystemUiOverlayStyle cannot affect that window.
class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final systemUiStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarContrastEnforced: false,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}
