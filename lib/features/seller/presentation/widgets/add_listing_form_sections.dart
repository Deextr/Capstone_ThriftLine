import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/add_listing_controller.dart' show ListingFormat;

/// Section title + optional helper text; no heavy card wrapper.
class ListingFormSection extends StatelessWidget {
  const ListingFormSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.subheading),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

@Deprecated('Use ListingFormSection')
typedef AddListingFormSection = ListingFormSection;

/// Matches server: `ends_at = now() + make_interval(days => duration_days)`.
String formatAuctionEndPreview(DateTime endsAt) {
  return DateFormat('MMM d, yyyy • h:mm a').format(endsAt.toLocal());
}

DateTime previewAuctionEndFromDays(int days) {
  return DateTime.now().add(Duration(days: days));
}

class ListingFormatTypeRow extends StatelessWidget {
  const ListingFormatTypeRow({
    super.key,
    required this.selectedFormat,
    required this.onFormatSelected,
  });

  final ListingFormat selectedFormat;
  final ValueChanged<ListingFormat> onFormatSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FormatCard(
          label: 'Fixed price',
          icon: Icons.sell_outlined,
          format: ListingFormat.fixedPrice,
          selectedFormat: selectedFormat,
          onTap: () => onFormatSelected(ListingFormat.fixedPrice),
        ),
        const SizedBox(width: 8),
        _FormatCard(
          label: 'Auction',
          icon: Icons.gavel_outlined,
          format: ListingFormat.auction,
          selectedFormat: selectedFormat,
          onTap: () => onFormatSelected(ListingFormat.auction),
        ),
      ],
    );
  }
}

class ListingAuctionQuantityNote extends StatelessWidget {
  const ListingAuctionQuantityNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Quantity is 1. Auction listings are a single unique item.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuctionDurationSelector extends StatelessWidget {
  const AuctionDurationSelector({
    super.key,
    required this.selectedDays,
    required this.onDaysSelected,
    required this.previewEndsAt,
    this.durationError,
  });

  final int selectedDays;
  final ValueChanged<int> onDaysSelected;
  final DateTime previewEndsAt;
  final String? durationError;

  static const _dayOptions = [1, 3, 5, 7];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose how long buyers can place bids.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final cellWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: _dayOptions.map((days) {
                final selected = selectedDays == days;
                return SizedBox(
                  width: cellWidth,
                  child: _DurationOptionTile(
                    label: days == 1 ? '1 day' : '$days days',
                    selected: selected,
                    onTap: () => onDaysSelected(days),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bidding ends approximately',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatAuctionEndPreview(previewEndsAt),
                      style: AppTypography.label.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (durationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              durationError!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class BidIncrementSelector extends StatelessWidget {
  const BidIncrementSelector({
    super.key,
    required this.selectedIncrement,
    required this.onIncrementSelected,
    this.incrementError,
  });

  final double selectedIncrement;
  final ValueChanged<double> onIncrementSelected;
  final String? incrementError;

  static const _increments = [10.0, 20.0, 50.0, 100.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Minimum amount each new bid must beat the current high bid.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _increments.map((value) {
            final selected = selectedIncrement == value;
            return _DurationOptionTile(
              label: '₱${value.toInt()}',
              selected: selected,
              compact: true,
              onTap: () => onIncrementSelected(value),
            );
          }).toList(),
        ),
        if (incrementError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              incrementError!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.label,
    required this.icon,
    required this.format,
    required this.selectedFormat,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final ListingFormat format;
  final ListingFormat selectedFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedFormat == format;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationOptionTile extends StatelessWidget {
  const _DurationOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 12,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: compact
              ? Text(
                  label,
                  style: AppTypography.label.copyWith(
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AppTypography.label.copyWith(
                          color: selected
                              ? AppColors.primaryDark
                              : AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
