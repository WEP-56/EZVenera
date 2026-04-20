import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../navigation/app_destination.dart';
import '../pages/categories_page.dart';
import '../pages/local_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../pages/sources_page.dart';
import '../state/app_state_controller.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int selectedIndex;
  late final List<Widget> _pages;

  static const destinations = AppDestination.values;

  @override
  void initState() {
    super.initState();
    final restoredIndex = AppStateController.instance.getInt('shell.selectedIndex');
    if (restoredIndex != null &&
        restoredIndex >= 0 &&
        restoredIndex < destinations.length) {
      selectedIndex = restoredIndex;
    } else {
      selectedIndex = 0;
    }
    _pages = const [
      SearchPage(),
      CategoriesPage(),
      LocalPage(),
      SourcesPage(),
      SettingsPage(),
    ];
  }

  bool get useDesktopLayout {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
        return false;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = destinations[selectedIndex];
    final content = IndexedStack(index: selectedIndex, children: _pages);

    return Scaffold(
      body: useDesktopLayout
          ? _DesktopShell(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              destination: destination,
              child: content,
            )
          : _MobileShell(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              destination: destination,
              child: content,
            ),
    );
  }

  void onSelect(int index) {
    if (index == selectedIndex) {
      return;
    }
    setState(() {
      selectedIndex = index;
    });
    AppStateController.instance.setInt('shell.selectedIndex', index);
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.selectedIndex,
    required this.onSelect,
    required this.destination,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppDestination destination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 288,
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EZVenera',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Windows and Android only. Plugin-first architecture.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelect,
                      backgroundColor: Colors.transparent,
                      indicatorColor: theme.colorScheme.secondaryContainer,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final item in AppDestination.values)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.selectedIndex,
    required this.onSelect,
    required this.destination,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppDestination destination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(destination.title), centerTitle: false),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final item in AppDestination.values)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
