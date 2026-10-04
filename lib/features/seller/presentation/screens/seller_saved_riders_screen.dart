import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_saved_riders_controller.dart';
import '../../data/seller_saved_rider.dart';

class SellerSavedRidersScreen extends StatelessWidget {
  const SellerSavedRidersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SellerSavedRidersController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Riders'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final created = await context.push<SellerSavedRider>(
            RouteNames.sellerSavedRiderEditor,
          );
          if (created != null && context.mounted) {
            await context.read<SellerSavedRidersController>().load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add rider'),
      ),
      body: ctrl.isLoading
          ? ListView(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              children: const [
                SkeletonBox(width: double.infinity, height: 72),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 72),
              ],
            )
          : ctrl.errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingMd),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ctrl.errorMessage!,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: ctrl.load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ctrl.riders.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppConstants.spacingMd),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.two_wheeler_outlined,
                              size: 48,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Save riders you use often',
                              style: AppTypography.subheading,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'When arranging delivery, pick a saved rider '
                              'instead of typing the same details every time.',
                              style: AppTypography.caption,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingMd,
                        AppConstants.spacingMd,
                        AppConstants.spacingMd,
                        88,
                      ),
                      itemCount: ctrl.riders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final rider = ctrl.riders[index];
                        return _RiderTile(rider: rider);
                      },
                    ),
    );
  }
}

class _RiderTile extends StatelessWidget {
  const _RiderTile({required this.rider});

  final SellerSavedRider rider;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove rider?'),
        content: Text(
          '${rider.riderName} will be removed from your saved riders. '
          'Orders already dispatched keep their assigned rider details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final error = await context
        .read<SellerSavedRidersController>()
        .deleteRider(rider.id);
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
    } else {
      showThriftSnackBar(context, 'Rider removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deleting = context.watch<SellerSavedRidersController>().isDeleting;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final updated = await context.push<SellerSavedRider>(
            '${RouteNames.sellerSavedRiderEditor}?id=${rider.id}',
          );
          if (updated != null && context.mounted) {
            await context.read<SellerSavedRidersController>().load();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.primary,
                child: Text(
                  rider.riderName.isNotEmpty
                      ? rider.riderName[0].toUpperCase()
                      : '?',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rider.riderName, style: AppTypography.label),
                    const SizedBox(height: 2),
                    Text(
                      '${rider.maskedPhone} · ${rider.vehicle.label}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final updated = await context.push<SellerSavedRider>(
                    '${RouteNames.sellerSavedRiderEditor}?id=${rider.id}',
                  );
                  if (updated != null && context.mounted) {
                    await context
                        .read<SellerSavedRidersController>()
                        .load();
                  }
                },
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: deleting ? null : () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
