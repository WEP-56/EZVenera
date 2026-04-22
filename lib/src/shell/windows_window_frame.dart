import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state_controller.dart';

const kWindowsTitleBarHeight = 40.0;

class WindowsWindowFrame extends StatelessWidget {
  const WindowsWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return child;
    }

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const _WindowsTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WindowsTitleBar extends StatefulWidget {
  const _WindowsTitleBar();

  @override
  State<_WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<_WindowsTitleBar>
    with WindowListener {
  bool isMaximized = false;
  bool _appStateReady = false;
  bool _persistScheduled = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncWindowState();
    _waitForAppState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        isMaximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        isMaximized = false;
      });
    }
    _schedulePersistWindowSize();
  }

  @override
  void onWindowResize() {
    _schedulePersistWindowSize();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        height: kWindowsTitleBarHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _toggleMaximize,
                child: DragToMoveArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('EZVenera', style: titleStyle),
                    ),
                  ),
                ),
              ),
            ),
            _WindowControlButton(
              icon: Icons.remove_rounded,
              onPressed: () => windowManager.minimize(),
            ),
            _WindowControlButton(
              icon: isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              onPressed: _toggleMaximize,
            ),
            _WindowControlButton(
              icon: Icons.close_rounded,
              hoverColor: const Color(0xFFE5484D),
              foregroundColor: Colors.white,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (!mounted) {
      return;
    }
    setState(() {
      isMaximized = maximized;
    });
  }

  Future<void> _waitForAppState() async {
    if (AppStateController.instance.isInitialized) {
      _appStateReady = true;
      return;
    }
    await AppStateController.instance.initialize();
    _appStateReady = true;
  }

  void _schedulePersistWindowSize() {
    if (_persistScheduled) {
      return;
    }
    _persistScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 220), () async {
      _persistScheduled = false;
      if (!mounted || !_appStateReady) {
        return;
      }
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final size = await windowManager.getSize();
      await AppStateController.instance.setSection(
        'window.bounds',
        <String, dynamic>{'width': size.width, 'height': size.height},
      );
    });
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.foregroundColor,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final Color? hoverColor;
  final Color? foregroundColor;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool isHovering = false;
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCloseButton = widget.hoverColor != null;
    final hoverColor =
        widget.hoverColor ?? theme.colorScheme.secondaryContainer;
    final defaultForeground = theme.colorScheme.onSurfaceVariant;
    final foreground = isHovering
        ? (widget.foregroundColor ?? defaultForeground)
        : defaultForeground;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) {
        setState(() {
          isHovering = false;
          isPressed = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => isPressed = true),
        onTapCancel: () => setState(() => isPressed = false),
        onTapUp: (_) => setState(() => isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 46,
          height: double.infinity,
          color: isHovering
              ? (isPressed
                    ? hoverColor.withValues(alpha: isCloseButton ? 0.82 : 0.72)
                    : hoverColor)
              : Colors.transparent,
          child: Icon(widget.icon, size: 18, color: foreground),
        ),
      ),
    );
  }
}
