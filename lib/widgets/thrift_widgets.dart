import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_typography.dart';

enum ThriftButtonVariant { primary, secondary, outline, ghost }

class ThriftButton extends StatelessWidget {
  const ThriftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ThriftButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.expand = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final ThriftButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(label, style: AppTypography.label.copyWith(fontSize: 14, color: _textColor)),
            ],
          );

    final btn = switch (variant) {
      ThriftButtonVariant.primary => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: Size(expand ? double.infinity : 0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: child,
        ),
      ThriftButtonVariant.secondary => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? AppColors.secondary,
            foregroundColor: Colors.white,
            minimumSize: Size(expand ? double.infinity : 0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: child,
        ),
      ThriftButtonVariant.outline => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color ?? AppColors.primary,
            minimumSize: Size(expand ? double.infinity : 0, 48),
            side: BorderSide(color: color ?? AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: child,
        ),
      ThriftButtonVariant.ghost => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: color ?? AppColors.primary,
            minimumSize: Size(expand ? double.infinity : 0, 48),
          ),
          child: child,
        ),
    };

    return btn;
  }

  Color get _textColor => variant == ThriftButtonVariant.outline || variant == ThriftButtonVariant.ghost
      ? (color ?? AppColors.primary)
      : Colors.white;
}

class ThriftTextField extends StatelessWidget {
  const ThriftTextField({
    super.key,
    this.label,
    this.hint,
    this.error,
    this.controller,
    this.obscureText = false,
    this.icon,
    this.suffix,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
  });

  final String? label;
  final String? hint;
  final String? error;
  final TextEditingController? controller;
  final bool obscureText;
  final IconData? icon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppConstants.spacingXs),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onTap: onTap,
          readOnly: readOnly,
          autofocus: autofocus,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, color: AppColors.textHint, size: 20) : null,
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            errorText: error,
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
          ),
        ),
      ],
    );
  }
}

class ThriftCard extends StatelessWidget {
  const ThriftCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

enum BadgeVariant { primary, secondary, success, error, warning, neutral }

class ThriftBadge extends StatelessWidget {
  const ThriftBadge({super.key, required this.label, this.variant = BadgeVariant.primary});

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      BadgeVariant.primary => (AppColors.primaryLight, AppColors.primaryDark),
      BadgeVariant.secondary => (const Color(0xFFFFEDD5), AppColors.secondary),
      BadgeVariant.success => (const Color(0xFFD1FAE5), AppColors.success),
      BadgeVariant.error => (const Color(0xFFFEE2E2), AppColors.error),
      BadgeVariant.warning => (const Color(0xFFFEF3C7), AppColors.warning),
      BadgeVariant.neutral => (AppColors.surfaceVariant, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: AppTypography.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class ThriftAvatar extends StatelessWidget {
  const ThriftAvatar({
    super.key,
    required this.imageUrl,
    this.size = 40,
    this.showOnline = false,
  });

  final String imageUrl;
  final double size;
  final bool showOnline;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundImage: NetworkImage(imageUrl),
          backgroundColor: AppColors.primaryLight,
        ),
        if (showOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class ThriftChip extends StatelessWidget {
  const ThriftChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primaryLight,
        checkmarkColor: AppColors.primary,
        labelStyle: AppTypography.caption.copyWith(
          color: selected ? AppColors.primaryDark : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

class ThriftBottomSheet extends StatelessWidget {
  const ThriftBottomSheet({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  static Future<T?> show<T>(BuildContext context, {required Widget child, String? title}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ThriftBottomSheet(title: title, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(title!, style: AppTypography.heading),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showThriftSnackBar(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
