import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/report_appeal_controller.dart';
import '../../data/report_appeal.dart';

class ReportAppealScreen extends StatelessWidget {
  const ReportAppealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportAppealController>();
    final appeal = controller.appeal;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Account review'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: controller.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : appeal == null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
                  child: Column(
                    children: [
                      Text(
                        controller.errorMessage ?? 'Review not found.',
                        style: AppTypography.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ThriftButton(
                        label: 'Try again',
                        onPressed: context.read<ReportAppealController>().load,
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Text('Account review update', style: AppTypography.heading),
                    const SizedBox(height: 8),
                    Text(
                      'A community report involving your account has been reviewed. Reporter details are not shared.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (appeal.underReview)
                      Text(
                        'This report is still under review.',
                        style: AppTypography.body,
                      )
                    else if (appeal.alreadySubmitted) ...[
                      Text('Appeal sent', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      Text(
                        appeal.details?.trim().isNotEmpty == true
                            ? appeal.details!.trim()
                            : 'Your appeal was recorded.',
                        style: AppTypography.body,
                      ),
                      if (appeal.createdAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sent ${formatCompactDate(appeal.createdAt!)}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ] else if (appeal.canAppeal) ...[
                      Text('Send an appeal', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      Text(
                        'Explain what you would like reviewed. This does not change the original report.',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 12),
                      ThriftTextField(
                        label: 'Appeal',
                        hint: 'Write a short explanation.',
                        controller: controller.detailsController,
                        maxLines: 6,
                        error: controller.details.trim().isEmpty
                            ? null
                            : appealDetailsError(controller.details),
                        onChanged: context
                            .read<ReportAppealController>()
                            .setDetails,
                      ),
                      const SizedBox(height: 16),
                      ThriftButton(
                        label: 'Send appeal',
                        isLoading: controller.isSaving,
                        onPressed: controller.canSubmit
                            ? () => _submit(context)
                            : null,
                      ),
                    ] else
                      Text(
                        'This review cannot be appealed.',
                        style: AppTypography.body,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final error = await context.read<ReportAppealController>().submit();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Appeal sent.');
  }
}
