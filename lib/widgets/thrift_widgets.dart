import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
          backgroundColor: AppColors.primaryLight,
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: size,
                height: size,
                color: AppColors.primaryLight,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: AppColors.primary,
                ),
              ),
              errorWidget: (_, _, _) => Container(
                width: size,
                height: size,
                color: AppColors.primaryLight,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
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

class TrustClassificationData {
  final String label;
  final int minScore;
  final int maxScore;
  final Color color;
  final IconData icon;
  final String description;

  const TrustClassificationData({
    required this.label,
    required this.minScore,
    required this.maxScore,
    required this.color,
    required this.icon,
    required this.description,
  });
}

const List<TrustClassificationData> trustClassifications = [
  TrustClassificationData(
    label: 'Highly Trusted Seller',
    minScore: 90,
    maxScore: 100,
    color: Color(0xFF0D9488), // Teal
    icon: Icons.verified_user_rounded,
    description: 'Outstanding fulfillment speed, near-zero complaints, and highly rated items.',
  ),
  TrustClassificationData(
    label: 'Trusted Seller',
    minScore: 75,
    maxScore: 89,
    color: Color(0xFF10B981), // Emerald/Green
    icon: Icons.shield_rounded,
    description: 'Consistently positive reviews, reliable shipping, and accurate descriptions.',
  ),
  TrustClassificationData(
    label: 'Developing Seller',
    minScore: 60,
    maxScore: 74,
    color: Color(0xFFF59E0B), // Amber
    icon: Icons.trending_up_rounded,
    description: 'Newer shop building community presence or has minor feedback history.',
  ),
  TrustClassificationData(
    label: 'Under Review',
    minScore: 40,
    maxScore: 59,
    color: Color(0xFFF97316), // Orange
    icon: Icons.gpp_maybe_rounded,
    description: 'Undergoing audit due to reports, high cancellation rate, or low ratings.',
  ),
  TrustClassificationData(
    label: 'Banned',
    minScore: 0,
    maxScore: 39,
    color: Color(0xFFEF4444), // Red
    icon: Icons.gpp_bad_rounded,
    description: 'Accounts suspended due to serious policy violations or scam complaints.',
  ),
];

class SellerTrustBadge extends StatelessWidget {
  const SellerTrustBadge({
    super.key,
    required this.trustScore,
    required this.isVerified,
    required this.shopName,
  });

  final int trustScore;
  final bool isVerified;
  final String shopName;

  @override
  Widget build(BuildContext context) {
    final current = trustClassifications.firstWhere(
      (c) => trustScore >= c.minScore && trustScore <= c.maxScore,
      orElse: () => trustClassifications.last,
    );

    return InkWell(
      onTap: () => _showTrustInfoBottomSheet(context, current),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: current.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: current.color.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              current.icon,
              color: current.color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              '${current.label} ($trustScore/100)',
              style: AppTypography.caption.copyWith(
                color: current.color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline_rounded,
              color: current.color.withValues(alpha: 0.6),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }

  void _showTrustInfoBottomSheet(BuildContext context, TrustClassificationData current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const SizedBox(height: 20),
              Text(
                'Trust & Verification',
                style: AppTypography.heading.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'How we ensure ThriftLine remains a safe community',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: current.color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(current.icon, color: current.color, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shopName,
                                      style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Trust Score: ',
                                          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                                        ),
                                        Text(
                                          '$trustScore/100',
                                          style: AppTypography.body.copyWith(
                                            color: current.color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isVerified)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.verified, color: AppColors.primary, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Verified',
                                        style: TextStyle(
                                          color: AppColors.primaryDark,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 1),
                          Text(
                            isVerified
                                ? '$shopName is a verified seller and currently rated as a ${current.label} based on their positive community feedback, fulfillment efficiency, and safety compliance.'
                                : '$shopName is currently classified as a ${current.label} with a trust score of $trustScore/100.',
                            style: AppTypography.body.copyWith(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Seller Trust Classifications',
                      style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ...trustClassifications.map((item) {
                      final isCurrent = item.label == current.label;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent ? item.color : AppColors.border.withValues(alpha: 0.5),
                            width: isCurrent ? 2 : 1,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: item.color.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(item.icon, color: item.color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        item.label,
                                        style: AppTypography.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: isCurrent ? item.color : AppColors.textPrimary,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.color.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${item.minScore}-${item.maxScore}',
                                          style: AppTypography.caption.copyWith(
                                            color: item.color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.description,
                                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: item.color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Current Status',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryLight),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Identity Verified Status',
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Verified sellers have completed government-issued ID verification and face-match checks. This helps prevent fraud and ensures you are buying from a real, accountability-checked individual.',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primaryDark.withValues(alpha: 0.8),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
