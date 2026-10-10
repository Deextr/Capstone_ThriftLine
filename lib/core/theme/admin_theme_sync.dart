import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_palette.dart';
import '../../providers/theme_provider.dart';

/// Binds [AppPalette.current] to the active admin theme and registers a
/// dependency so descendants rebuild when [ThemeProvider] changes.
///
/// Prefer wrapping the full admin shell (see [AdminWebShell]) so chrome and
/// content switch in one frame. Use this wrapper for auth screens outside the
/// shell when they must react to theme toggles.
class AdminThemeSync extends StatelessWidget {
  const AdminThemeSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final palette =
        Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    AppPalette.current = palette;
    return child;
  }
}
