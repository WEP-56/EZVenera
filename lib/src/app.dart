import 'package:flutter/material.dart';

import 'bootstrap/app_bootstrap.dart';
import 'settings/settings_controller.dart';

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
    const seedColor = Color(0xFF0F766E);

    return MaterialApp(
      title: 'EZVenera',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
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
