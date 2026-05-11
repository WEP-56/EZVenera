import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../settings/settings_controller.dart';

/// Segmented toggle that switches between [ComicDisplayMode.grid] and
/// [ComicDisplayMode.list] using the shared [SettingsController].
///
/// Listens to the controller so the UI always mirrors the persisted value,
/// and writes back immediately - the setting is remembered across launches.
class ComicDisplayToggle extends StatelessWidget {
  const ComicDisplayToggle({super.key, this.dense = false});

  /// When true, uses a compact icon-button styling. Used by the search header
  /// where space is limited.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: SettingsController.instance,
      builder: (context, _) {
        final mode = SettingsController.instance.comicDisplayMode;
        final next = mode == ComicDisplayMode.grid
            ? ComicDisplayMode.list
            : ComicDisplayMode.grid;
        final icon = mode == ComicDisplayMode.grid
            ? Icons.view_list_rounded
            : Icons.grid_view_rounded;
        final tooltip = mode == ComicDisplayMode.grid
            ? l10n.comicDisplayShowList
            : l10n.comicDisplayShowGrid;

        if (dense) {
          return IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: () =>
                SettingsController.instance.setComicDisplayMode(next),
          );
        }

        return Tooltip(
          message: tooltip,
          child: FilledButton.tonalIcon(
            onPressed: () =>
                SettingsController.instance.setComicDisplayMode(next),
            icon: Icon(icon, size: 18),
            label: Text(tooltip),
          ),
        );
      },
    );
  }
}
