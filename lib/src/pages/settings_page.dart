import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../settings/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final controller = SettingsController.instance;
  late final TextEditingController sourceIndexController =
      TextEditingController(text: controller.sourceIndexUrl);

  @override
  void initState() {
    super.initState();
    controller.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onSettingsChanged);
    sourceIndexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          _SettingsGroup(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            children: [
              ListTile(
                title: const Text('Theme Mode'),
                subtitle: Text(_themeModeLabel(controller.themeMode)),
                trailing: DropdownButton<ThemeMode>(
                  value: controller.themeMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.setThemeMode(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: 'Network',
            icon: Icons.public_outlined,
            children: [
              ListTile(
                title: const Text('Source Index URL'),
                subtitle: Text(
                  controller.sourceIndexUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: sourceIndexController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Index URL',
                        hintText: SettingsController.defaultSourceIndexUrl,
                      ),
                      onSubmitted: (value) =>
                          controller.setSourceIndexUrl(value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () {
                            controller.setSourceIndexUrl(
                              sourceIndexController.text,
                            );
                          },
                          child: const Text('Save'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {
                            sourceIndexController.text =
                                SettingsController.defaultSourceIndexUrl;
                            controller.setSourceIndexUrl(
                              SettingsController.defaultSourceIndexUrl,
                            );
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: 'App',
            icon: Icons.apps_outlined,
            children: [
              ListTile(
                title: const Text('Downloaded Comics'),
                subtitle: Text(
                  '${DownloadController.instance.downloads.length} saved comic(s)',
                ),
              ),
              ListTile(
                title: const Text('Reset Settings'),
                subtitle: const Text(
                  'Reset theme mode and source index URL to EZVenera defaults.',
                ),
                trailing: const Icon(Icons.restore),
                onTap: _confirmReset,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            title: 'About',
            icon: Icons.info_outline,
            children: const [
              ListTile(
                title: Text('EZVenera'),
                subtitle: Text(
                  'A simplified, maintainable fork direction of Venera focused on Windows, Android, plugin compatibility, and long-term clarity.',
                ),
              ),
              ListTile(
                title: Text('Source Repository'),
                subtitle: Text(
                  'EZVenera-config is the default plugin index for this app.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset Settings'),
          content: const Text('Reset current EZVenera settings to defaults?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await controller.reset();
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    if (sourceIndexController.text != controller.sourceIndexUrl) {
      sourceIndexController.text = controller.sourceIndexUrl;
    }
    setState(() {});
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
