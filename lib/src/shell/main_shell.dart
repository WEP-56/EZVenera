import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../navigation/app_destination.dart';
import '../pages/placeholder_page.dart';
import '../pages/search_page.dart';
import '../pages/sources_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  static const destinations = AppDestination.values;

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

    return Scaffold(
      body: useDesktopLayout
          ? _DesktopShell(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              destination: destination,
            )
          : _MobileShell(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              destination: destination,
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
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.selectedIndex,
    required this.onSelect,
    required this.destination,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppDestination destination;

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
        Expanded(child: _buildPage(destination)),
      ],
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.selectedIndex,
    required this.onSelect,
    required this.destination,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(destination.title), centerTitle: false),
      body: _buildPage(destination),
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

Widget _buildPage(AppDestination destination) {
  if (destination == AppDestination.search) {
    return const SearchPage();
  }
  if (destination == AppDestination.sources) {
    return const SourcesPage();
  }
  return PlaceholderPage(
    key: ValueKey(destination.name),
    title: destination.title,
    description: destination.description,
  );
}
