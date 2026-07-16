import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final reports = data.reports;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: reports.isEmpty
            ? _buildEmptyState(context)
            : ListView(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                children: [
                  // Trust score header
                  _buildTrustScoreHeader(),
                  const SizedBox(height: 20),

                  // Report count summary
                  Row(
                    children: [
                      Expanded(child: _statCard('Total', '${reports.length}', AppColors.textPrimary)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          'Under Review',
                          '${reports.where((r) => r.status == 'under_review').length}',
                          AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          'Resolved',
                          '${reports.where((r) => r.status == 'resolved' || r.status == 'action_taken').length}',
                          AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text('Report History', style: AppTypography.subheading),
                  const SizedBox(height: 12),

                  ...reports.map((report) => _buildReportCard(context, report, data)),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_outlined, size: 56, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text('No Reports Filed', style: AppTypography.heading),
            const SizedBox(height: 8),
            Text(
              'You haven\'t submitted any reports yet. If you encounter suspicious activity, you can report it from a seller\'s profile page.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustScoreHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.primary.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trust & Safety Center',
                  style: AppTypography.subheading.copyWith(color: AppColors.primaryDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track your reports and help maintain a safe community for all users.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(value, style: AppTypography.heading.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, ReportModel report, DataProvider data) {
    final statusInfo = _getStatusInfo(report.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Report header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(statusInfo.icon, size: 20, color: statusInfo.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report.category,
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Against @${report.sellerUsername}',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusInfo.label,
                        style: AppTypography.caption.copyWith(
                          color: statusInfo.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (report.details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    report.details,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(_formatDate(report.createdAt), style: AppTypography.caption.copyWith(fontSize: 11)),
                    const Spacer(),
                    if (report.evidenceCount > 0) ...[
                      Icon(Icons.attach_file, size: 14, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        '${report.evidenceCount} evidence',
                        style: AppTypography.caption.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),

                // Admin response
                if (report.adminResponse != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.admin_panel_settings_outlined, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Admin Response',
                              style: AppTypography.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.adminResponse!,
                          style: AppTypography.body.copyWith(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons based on status
          if (report.status == 'dismissed' || report.status == 'resolved') ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (report.status == 'dismissed' && !report.hasAppealed) ...[
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.warning,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.gavel_outlined, size: 18),
                        label: const Text('Appeal Decision'),
                        onPressed: () => _showAppealDialog(context, report, data),
                      ),
                    ),
                  ],
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                      onPressed: () => data.removeReport(report.id),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (report.hasAppealed) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel, size: 14, color: AppColors.info),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Appeal submitted — under secondary review',
                      style: AppTypography.caption.copyWith(color: AppColors.info, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAppealDialog(BuildContext context, ReportModel report, DataProvider data) {
    final appealCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.gavel_outlined, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            Text('Appeal Decision', style: AppTypography.heading.copyWith(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If you believe this report was dismissed incorrectly, you can appeal the decision. Our senior team will conduct a second review.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Original Report', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(report.category, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                  if (report.details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      report.details,
                      style: AppTypography.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: appealCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Explain why you believe this should be reconsidered...',
                hintStyle: AppTypography.caption,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.gavel, size: 18),
            label: const Text('Submit Appeal'),
            onPressed: () {
              data.appealReport(
                report.id,
                appealCtrl.text.trim().isEmpty
                    ? 'I believe this report was dismissed without thorough investigation.'
                    : appealCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              showThriftSnackBar(context, 'Appeal submitted! A senior reviewer will re-examine your case.');
            },
          ),
        ],
      ),
    );
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'under_review':
        return _StatusInfo('Under Review', AppColors.warning, Icons.hourglass_empty_rounded);
      case 'action_taken':
        return _StatusInfo('Action Taken', AppColors.success, Icons.check_circle_outline);
      case 'resolved':
        return _StatusInfo('Resolved', AppColors.success, Icons.verified_outlined);
      case 'dismissed':
        return _StatusInfo('Dismissed', AppColors.textSecondary, Icons.cancel_outlined);
      default:
        return _StatusInfo('Pending', AppColors.info, Icons.schedule_outlined);
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}
