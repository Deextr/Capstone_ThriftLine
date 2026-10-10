import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'app_palette.dart';

/// Notifies when the animated [Theme]'s [AppPalette] extension changes.
class AppPaletteLerpNotify extends ChangeNotifier {
  AppPaletteLerpNotify._();

  static final AppPaletteLerpNotify instance = AppPaletteLerpNotify._();

  void pulse() => notifyListeners();
}

/// Syncs [AppPalette.current] with [MaterialApp]'s animated theme.
class AppPaletteLerpSync extends StatefulWidget {
  const AppPaletteLerpSync({super.key, required this.child});

  final Widget child;

  @override
  State<AppPaletteLerpSync> createState() => _AppPaletteLerpSyncState();
}

class _AppPaletteLerpSyncState extends State<AppPaletteLerpSync> {
  Color? _lastBackground;
  Color? _lastSurface;
  Color? _lastTextPrimary;

  AppPalette _readPalette(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
  }

  void _publishPalette(AppPalette palette, {required bool notify}) {
    AppPalette.current = palette;
    if (_lastBackground == null) {
      _lastBackground = palette.background;
      _lastSurface = palette.surface;
      _lastTextPrimary = palette.textPrimary;
      return;
    }
    final changed = _lastBackground != palette.background ||
        _lastSurface != palette.surface ||
        _lastTextPrimary != palette.textPrimary;
    _lastBackground = palette.background;
    _lastSurface = palette.surface;
    _lastTextPrimary = palette.textPrimary;
    if (notify && changed) {
      AppPaletteLerpNotify.instance.pulse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publishPalette(_readPalette(context), notify: true);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;
    Theme.of(context);
    _publishPalette(_readPalette(context), notify: false);

    return KeyedSubtree(
      key: ValueKey<ThemeMode>(themeMode),
      child: widget.child,
    );
  }
}

/// Rebuilds admin route content while palette tokens animate.
class AppPaletteLerpChild extends StatelessWidget {
  const AppPaletteLerpChild({super.key, required this.child});

  final Widget child;

  static int _paletteKey(AppPalette palette) {
    return Object.hash(
      palette.background.toARGB32(),
      palette.surface.toARGB32(),
      palette.sidebarSurface.toARGB32(),
      palette.textPrimary.toARGB32(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPaletteLerpNotify.instance,
      builder: (context, _) {
        Theme.of(context);
        final palette =
            Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
        AppPalette.current = palette;
        return KeyedSubtree(
          key: ValueKey<int>(_paletteKey(palette)),
          child: child,
        );
      },
    );
  }
}
