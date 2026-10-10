import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/marketplace_report_export_progress.dart';

/// Non-dismissible export progress shown while PDF/Excel is generated.
class MarketplaceReportExportProgressDialog extends StatelessWidget {
  const MarketplaceReportExportProgressDialog({
    super.key,
    required this.progress,
    this.title = 'Exporting report',
  });

  final MarketplaceReportExportProgress progress;
  final String title;

  @override
  Widget build(BuildContext context) {
    final percent = progress.percent;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title, style: AppTypography.sectionTitle),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                progress.message,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.fraction.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: AppTypography.sectionTitle.copyWith(
                  fontSize: 20,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
