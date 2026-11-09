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
    final eink = settings.einkMode;
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
      // Toggling E-Ink mode repaints the whole shell; a 200ms cross-fade on a
      // 1-bit panel is one more full-screen refresh for nothing.
      themeAnimationDuration: eink ? Duration.zero : kThemeAnimationDuration,
      theme: _themeFor(eink, Brightness.light),
      darkTheme: _themeFor(eink, Brightness.dark),
      home: const AppBootstrap(),
    );
  }

  ThemeData _themeFor(bool eink, Brightness brightness) {
    final ThemeData base;
    if (eink && settings.einkHighContrast) {
      base = buildEinkThemeData(brightness);
    } else if (brightness == Brightness.dark) {
      base = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeSeedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
    } else {
      base = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeSeedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
        useMaterial3: true,
      );
    }
    // Framework-level motion (ink ripples, page transitions, theme fades) is
    // driven by the theme, not by the per-widget durations the pages zero
    // out — it must be gated here to apply at all (REQ-002).
    return eink ? applyEinkMotion(base) : base;
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
    // 1-bit panels threshold low-alpha ink into invisible dithered noise, so
    // borders/containers must be opaque; hierarchy comes from stroke width
    // and weight, not from alpha.
    outline: foreground,
    outlineVariant: foreground,
    primaryContainer: background,
    onPrimaryContainer: foreground,
    secondaryContainer: background,
    onSecondaryContainer: foreground,
    tertiaryContainer: background,
    onTertiaryContainer: foreground,
    errorContainer: background,
    onErrorContainer: foreground,
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

/// Framework-level motion gating for E-Ink (REQ-002).
///
/// Ink splashes, page transitions and theme fades are driven by the theme,
/// not by the per-widget durations the pages zero out; on a 1-bit panel every
/// animated frame costs a refresh cycle and leaves ghosting. Applied on top
/// of both the high-contrast E-Ink theme and the regular themes whenever
/// E-Ink mode is on. Public so widget tests can assert the gating.
ThemeData applyEinkMotion(ThemeData theme) {
  return theme.copyWith(
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const EinkNoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Page transition builder that shows the destination page immediately —
/// an animated push is several full-screen refreshes on E-Ink hardware.
class EinkNoPageTransitionsBuilder extends PageTransitionsBuilder {
  const EinkNoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
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
