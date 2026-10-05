import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/report_status.dart';
import '../../../../models/community_report_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/report_reasons.dart';

class OrderCommunityReportPanel extends StatelessWidget {
  const OrderCommunityReportPanel({
    super.key,
    required this.report,
    this.onReturned,
  });

  final CommunityReportModel report;
  final VoidCallback? onReturned;

  @override
  Widget build(BuildContext context) {
    final status = reportStatusFromDb(report.status);
    final color = reportStatusColor(status);
    final adminResponse = report.adminResponse?.trim();

    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flag_outlined, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reportReasonLabel(report.category),
                      style: AppTypography.subheading,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Report status',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reportStatusLabel(status),
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reportStatusDescription(status),
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          if (adminResponse != null && adminResponse.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Admin response', style: AppTypography.caption),
            const SizedBox(height: 4),
            Text(adminResponse, style: AppTypography.body),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await context.push(RouteNames.reportDetailFor(report.id));
                if (context.mounted) {
                  onReturned?.call();
                }
              },
              child: const Text('View report details'),
            ),
          ),
        ],
      ),
    );
  }
}
