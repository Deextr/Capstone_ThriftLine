import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../providers/theme_provider.dart';

/// Light/dark toggle shared by the admin login screen and authenticated shell.
class AdminThemeToggleButton extends StatelessWidget {
  const AdminThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = theme.isDarkMode;
    final label = isDark ? 'Switch to light mode' : 'Switch to dark mode';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surfaceVariant.withValues(alpha: 0.65),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: theme.toggleTheme,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                isDark ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
