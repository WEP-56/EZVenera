import 'package:flutter/material.dart';

import 'bootstrap/app_bootstrap.dart';

class EZVeneraApp extends StatelessWidget {
  const EZVeneraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF0F766E);

    return MaterialApp(
      title: 'EZVenera',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
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
}
