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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeSeedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
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
