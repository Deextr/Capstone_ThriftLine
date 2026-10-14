import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/looking_for_feed_query.dart';

/// One-line context for buyer vs seller Looking For workspaces.
class LookingForWorkspaceIntro extends StatelessWidget {
  const LookingForWorkspaceIntro({super.key, required this.sellerWorkspace});

  final bool sellerWorkspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        sellerWorkspace
            ? 'Browse what buyers need. Open a request or tap I Have This Item to message them.'
            : 'Post what you want to buy, browse community requests, and manage your own listings.',
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class LookingForRestrictionBanner extends StatelessWidget {
  const LookingForRestrictionBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort + filter entry row for browse and list tabs.
class LookingForFeedToolbar extends StatelessWidget {
  const LookingForFeedToolbar({
    super.key,
    required this.sort,
    required this.filters,
    required this.onSortChanged,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  final LookingForSort sort;
  final LookingForFeedFilters filters;
  final ValueChanged<LookingForSort> onSortChanged;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final filterCount = filters.activeFilterCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SortButton(sort: sort, onSortChanged: onSortChanged),
              ),
              const SizedBox(width: 10),
              _FilterButton(
                activeCount: filterCount,
                onPressed: onOpenFilters,
              ),
            ],
          ),
          if (filters.hasAnyFilter) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._activeFilterChips(filters),
                TextButton(
                  onPressed: onClearFilters,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear all',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _activeFilterChips(LookingForFeedFilters f) {
    final chips = <Widget>[];
    if (f.hasCategoryFilter) {
      for (final cat in f.categories) {
        chips.add(_ActiveChip(label: cat.label));
      }
    }
    if (f.hasBudgetFilter) {
      final min = f.minBudget;
      final max = f.maxBudget;
      final label = switch ((min, max)) {
        (null, final double m) => '≤ ${formatCurrency(m)}',
        (final double m, null) => '≥ ${formatCurrency(m)}',
        (final double a, final double b) =>
          '${formatCurrency(a)} – ${formatCurrency(b)}',
        _ => 'Budget',
      };
      chips.add(_ActiveChip(label: label));
    }
    if (f.referenceImageOnly) {
      chips.add(const _ActiveChip(label: 'With photo'));
    }
    if (f.withSizeOnly) {
      chips.add(const _ActiveChip(label: 'Has size'));
    }
    if (f.hasInactiveStatusFilter) {
      chips.add(
        _ActiveChip(
          label: switch (f.inactiveStatus) {
            LookingForInactiveStatusFilter.expired => 'Expired',
            LookingForInactiveStatusFilter.fulfilled => 'Fulfilled',
            LookingForInactiveStatusFilter.all => 'Status',
          },
        ),
      );
    }
    return chips;
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSortChanged});

  final LookingForSort sort;
  final ValueChanged<LookingForSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showSortMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.sort, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sort: ${lookingForSortShortLabel(sort)}',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.expand_more, size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sort by',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...LookingForSort.values.map((option) {
                final selected = option == sort;
                return ListTile(
                  title: Text(lookingForSortLabel(option)),
                  trailing: selected
                      ? Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    onSortChanged(option);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activeCount > 0
          ? AppColors.primaryLight.withValues(alpha: 0.45)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: 18,
                color: activeCount > 0
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                activeCount > 0 ? 'Filters ($activeCount)' : 'Filters',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: activeCount > 0
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class LookingForListSectionHeader extends StatelessWidget {
  const LookingForListSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.count,
  });

  final String title;
  final String subtitle;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
