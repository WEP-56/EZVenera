import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

enum AppDestination {
  search(icon: Icons.search_outlined, selectedIcon: Icons.search),
  category(icon: Icons.category_outlined, selectedIcon: Icons.category),
  local(icon: Icons.bookmarks_outlined, selectedIcon: Icons.bookmarks),
  sources(icon: Icons.extension_outlined, selectedIcon: Icons.extension),
  settings(icon: Icons.tune_outlined, selectedIcon: Icons.tune);

  const AppDestination({required this.icon, required this.selectedIcon});

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (this) {
      AppDestination.search => l10n.navLabel('search'),
      AppDestination.category => l10n.navLabel('category'),
      AppDestination.local => l10n.navLabel('local'),
      AppDestination.sources => l10n.navLabel('sources'),
      AppDestination.settings => l10n.navLabel('settings'),
    };
  }

  String title(BuildContext context) => label(context);
}
