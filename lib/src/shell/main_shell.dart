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
  static const _desktopSidebarWidth = 220.0;
  static const _desktopSidebarCollapsedWidth = 84.0;
  static const _desktopBreakpoint = 920.0;

  late int selectedIndex;
  late bool sidebarCollapsed;
  late final List<Widget> _pages;

  static const destinations = AppDestination.values;

  @override
  void initState() {
    super.initState();
    final restoredIndex = AppStateController.instance.getInt(
      'shell.selectedIndex',
    );
    if (restoredIndex != null &&
        restoredIndex >= 0 &&
        restoredIndex < destinations.length) {
      selectedIndex = restoredIndex;
    } else {
      selectedIndex = 0;
    }
    sidebarCollapsed =
        AppStateController.instance.getInt('shell.sidebarCollapsed') == 1;
    _pages = const [
      SearchPage(),
      CategoriesPage(),
      LocalPage(),
      SourcesPage(),
      SettingsPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final content = IndexedStack(index: selectedIndex, children: _pages);
    return LayoutBuilder(
      builder: (context, constraints) {
        final destination = destinations[selectedIndex];
        final useDesktopLayout =
            defaultTargetPlatform == TargetPlatform.windows &&
            constraints.maxWidth >= _desktopBreakpoint;

        if (useDesktopLayout) {
          return _DesktopShell(
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            sidebarCollapsed: sidebarCollapsed,
            onToggleSidebar: _toggleSidebar,
            child: content,
          );
        }

        return _MobileShell(
          selectedIndex: selectedIndex,
          onSelect: onSelect,
          destination: destination,
          child: content,
        );
      },
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

  void _toggleSidebar() {
    setState(() {
      sidebarCollapsed = !sidebarCollapsed;
    });
    AppStateController.instance.setInt(
      'shell.sidebarCollapsed',
      sidebarCollapsed ? 1 : 0,
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.selectedIndex,
    required this.onSelect,
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool sidebarCollapsed;
  final VoidCallback onToggleSidebar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const upperDestinations = [
      AppDestination.search,
      AppDestination.category,
      AppDestination.local,
      AppDestination.sources,
    ];

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: sidebarCollapsed
                ? _MainShellState._desktopSidebarCollapsedWidth
                : _MainShellState._desktopSidebarWidth,
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: _SidebarToggleButton(
                        collapsed: sidebarCollapsed,
                        onPressed: onToggleSidebar,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in upperDestinations) ...[
                      _SidebarDestinationButton(
                        destination: item,
                        selected: item.index == selectedIndex,
                        collapsed: sidebarCollapsed,
                        onTap: () => onSelect(item.index),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Spacer(),
                    _SidebarDestinationButton(
                      destination: AppDestination.settings,
                      selected: AppDestination.settings.index == selectedIndex,
                      collapsed: sidebarCollapsed,
                      onTap: () => onSelect(AppDestination.settings.index),
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
      ),
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
      appBar: AppBar(
        title: Text(destination.title(context)),
        centerTitle: false,
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final item in AppDestination.values)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label(context),
            ),
        ],
      ),
    );
  }
}

class _SidebarDestinationButton extends StatelessWidget {
  const _SidebarDestinationButton({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: collapsed ? destination.label(context) : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected
                  ? theme.colorScheme.secondaryContainer
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label(context),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: collapsed ? 'Expand Navigation' : 'Collapse Navigation',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.transparent,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!collapsed)
                  Text(
                    'Navigation',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Icon(
                  collapsed ? Icons.chevron_right : Icons.chevron_left,
                  color: foreground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
