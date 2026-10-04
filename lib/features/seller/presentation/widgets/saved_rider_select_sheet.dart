import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../data/seller_saved_rider.dart';

typedef SavedRiderSelectCallback = void Function(SellerSavedRider rider);

Future<void> showSavedRiderSelectSheet({
  required BuildContext context,
  required List<SellerSavedRider> riders,
  required SavedRiderSelectCallback onSelected,
  String? selectedId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppConstants.spacingMd,
            right: AppConstants.spacingMd,
            top: AppConstants.spacingMd,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom +
                AppConstants.spacingMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select rider', style: AppTypography.subheading),
              const SizedBox(height: 4),
              Text(
                'Choose a saved rider for this delivery.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 16),
              if (riders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No saved riders yet. Add one to fill details automatically.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: riders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final rider = riders[index];
                      final isSelected = rider.id == selectedId;
                      return Material(
                        color: isSelected
                            ? AppColors.primaryLight.withValues(alpha: 0.35)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            onSelected(rider);
                            Navigator.pop(sheetContext);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rider.riderName,
                                        style: AppTypography.label,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        rider.maskedPhone,
                                        style: AppTypography.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final created = await context.push<SellerSavedRider>(
                    RouteNames.sellerSavedRiderEditor,
                  );
                  if (created != null) {
                    onSelected(created);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add new rider'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
