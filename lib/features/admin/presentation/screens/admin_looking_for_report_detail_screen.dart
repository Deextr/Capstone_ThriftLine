import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../controllers/admin_looking_for_report_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/looking_for_moderation.dart';
import '../widgets/admin_review_widgets.dart';

class AdminLookingForReportDetailScreen extends StatelessWidget {
  const AdminLookingForReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminLookingForReportController>();
    final report = controller.report;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Looking For report'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const AdminDetailSkeleton()
            : report == null
            ? AdminErrorState(
                message:
                    controller.errorMessage ?? 'Unable to load this report.',
                onRetry: () =>
                    context.read<AdminLookingForReportController>().load(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text(
                    lookingForAdminStatusLabel(report.status),
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lookingForReportReasonLabel(report.reason) ?? report.reason,
                    style: AppTypography.heading,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted ${formatFullDate(report.createdAt)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 20),
                  Text('Request', style: AppTypography.label),
                  const SizedBox(height: 6),
                  Text(
                    report.postTitle,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (report.postDescription.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(report.postDescription, style: AppTypography.body),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    report.lifecycleLabel(controller.serverNow),
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (report.postCreatedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Posted ${formatFullDate(report.postCreatedAt!)}',
                      style: AppTypography.caption,
                    ),
                  ],
                  if (report.imageUrl != null &&
                      report.imageUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: report.imageUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  AdminDetailBlock(
                    label: 'People',
                    children: [
                      AdminKeyValueRow(
                        label: 'Reported',
                        value:
                            '${adminHandle(report.reportedUsername, report.reportedName)} · ${accountRoleLabel(report.reportedRole)}',
                      ),
                      AdminKeyValueRow(
                        label: 'Reporter',
                        value:
                            '${adminHandle(report.reporterUsername, report.reporterName)} · ${accountRoleLabel(report.reporterRole)}',
                      ),
                      AdminKeyValueRow(
                        label: 'Prior strikes',
                        value: '${report.confirmedViolations}',
                      ),
                    ],
                  ),
                  if (report.details.trim().isNotEmpty)
                    AdminDetailBlock(
                      label: 'Explanation',
                      children: [
                        Text(report.details, style: AppTypography.body),
                      ],
                    ),
                  if (controller.violations.isNotEmpty) ...[
                    Text('Confirmed violations', style: AppTypography.label),
                    const SizedBox(height: 8),
                    for (final item in controller.violations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Strike ${item.strikeNumber} · ${item.postTitle ?? 'Request'} · ${formatFullDate(item.createdAt)}',
                          style: AppTypography.caption,
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (report.canDecide) ...[
                    ThriftButton(
                      label: controller.isSaving ? 'Saving…' : 'Dismissed',
                      variant: ThriftButtonVariant.outline,
                      onPressed: controller.isSaving
                          ? null
                          : () => _decide(context, 'dismissed'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: controller.isSaving
                            ? null
                            : () => _confirm(context),
                        child: const Text(
                          'Confirmed violation',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm this violation?'),
        content: const Text(
          'The request will be removed and a strike will be recorded. This cannot be undone from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmed violation'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    await _decide(context, 'confirmed');
  }

  Future<void> _decide(BuildContext context, String decision) async {
    final error = await context.read<AdminLookingForReportController>().decide(
      decision,
    );
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      decision == 'confirmed' ? 'Violation confirmed.' : 'Report dismissed.',
    );
  }
}
