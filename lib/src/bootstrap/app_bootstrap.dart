import 'package:flutter/material.dart';

import '../downloads/download_controller.dart';
import '../library/favorite_controller.dart';
import '../library/history_controller.dart';
import '../plugin_runtime/plugin_runtime_controller.dart';
import '../settings/settings_controller.dart';
import '../shell/main_shell.dart';
import '../state/app_state_controller.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _future = _initialize();

  Future<void> _initialize() async {
    await SettingsController.instance.initialize();
    await AppStateController.instance.initialize();
    await PluginRuntimeController.instance.initialize();
    await DownloadController.instance.initialize();
    await HistoryController.instance.initialize();
    await FavoriteController.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapLoading();
        }

        if (snapshot.hasError) {
          return _BootstrapError(error: snapshot.error.toString());
        }

        return const MainShell();
      },
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to initialize EZVenera',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
