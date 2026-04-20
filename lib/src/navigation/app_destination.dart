import 'package:flutter/material.dart';

enum AppDestination {
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    title: 'Search',
    description: 'Original source-driven search flow will be migrated here.',
  ),
  category(
    label: 'Category',
    icon: Icons.category_outlined,
    selectedIcon: Icons.category,
    title: 'Category',
    description:
        'Category pages will stay compatible with the original source definitions.',
  ),
  local(
    label: 'Local',
    icon: Icons.bookmarks_outlined,
    selectedIcon: Icons.bookmarks,
    title: 'Local',
    description:
        'This page will contain history, favorites, and downloaded comics.',
  ),
  sources(
    label: 'Sources',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    title: 'Sources',
    description:
        'Source install, login, update, and source settings live here.',
  ),
  settings(
    label: 'Settings',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    title: 'Settings',
    description: 'Only effective settings for EZVenera will be kept.',
  );

  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.description,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String description;
}
