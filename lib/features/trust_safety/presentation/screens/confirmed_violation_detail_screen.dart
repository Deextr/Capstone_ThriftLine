import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/my_confirmed_violations_controller.dart';
import '../../data/confirmed_violation_labels.dart';
import '../../domain/confirmed_violation.dart';

class ConfirmedViolationDetailScreen extends StatefulWidget {
  const ConfirmedViolationDetailScreen({super.key});

  @override
  State<ConfirmedViolationDetailScreen> createState() =>
      _ConfirmedViolationDetailScreenState();
}

class _ConfirmedViolationDetailScreenState
    extends State<ConfirmedViolationDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConfirmedViolationDetailController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConfirmedViolationDetailController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Violation details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : controller.detail == null
            ? _ErrorBody(
                message: controller.errorMessage ?? 'Violation not found.',
                onRetry: () => controller.load(),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => controller.load(showSpinner: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _DetailBody(detail: controller.detail!),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final ConfirmedViolationDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final rows = <Widget>[
      _InfoRow(
        label: 'Violation type',
        value: confirmedViolationTypeHeading(summary),
      ),
      _InfoRow(
        label: 'Confirmed on',
        value: formatFullDate(summary.confirmedAt.toLocal()),
      ),
      _InfoRow(
        label: 'Status',
        value: confirmedViolationPenaltySummary(summary),
      ),
      if (summary.referenceTitle.isNotEmpty)
        _InfoRow(label: 'Related item', value: summary.referenceTitle),
    ];

    if (summary.source == 'looking_for' &&
        summary.reason != null &&
        summary.reason!.isNotEmpty) {
      rows.add(
        _InfoRow(
          label: 'Report category',
          value: lookingForReportReasonLabel(summary.reason!),
        ),
      );
    }

    if (detail.referenceDescription != null &&
        detail.referenceDescription!.trim().isNotEmpty) {
      rows.add(
        _InfoRow(label: 'Post details', value: detail.referenceDescription!),
      );
    }

    if (summary.source == 'community_report') {
      rows.add(
        _InfoRow(
          label: 'Report category',
          value: confirmedViolationCategoryLabel(summary.category),
        ),
      );
      final financial = resolutionFinancialLabel(detail.resolutionFinancial);
      if (financial.isNotEmpty) {
        rows.add(_InfoRow(label: 'Order outcome', value: financial));
      }
      if (detail.resolutionReturnRequired == true) {
        rows.add(
          const _InfoRow(
            label: 'Return',
            value: 'Buyer return required as part of resolution',
          ),
        );
      }
      final enforcement = enforcementReasonLabel(detail.enforcementReason);
      if (enforcement.isNotEmpty) {
        rows.add(_InfoRow(label: 'Why this was confirmed', value: enforcement));
      }
      if (summary.sourceKind == 'system') {
        rows.add(
          const _InfoRow(
            label: 'Source',
            value: 'Automatic enforcement after a missed deadline',
          ),
        );
      }
    }

    if (summary.source == 'auction_bidding') {
      if (detail.paymentDueAt != null) {
        rows.add(
          _InfoRow(
            label: 'Payment due',
            value: formatFullDate(detail.paymentDueAt!.toLocal()),
          ),
        );
      }
      if (detail.expiredAt != null) {
        rows.add(
          _InfoRow(
            label: 'Offer expired',
            value: formatFullDate(detail.expiredAt!.toLocal()),
          ),
        );
      }
      if (detail.totalViolations != null) {
        rows.add(
          _InfoRow(
            label: 'Total auction violations',
            value: '${detail.totalViolations}',
          ),
        );
      }
    }

    if (detail.totalStrikes != null && summary.source == 'looking_for') {
      rows.add(
        _InfoRow(label: 'Total Looking For strikes', value: '${detail.totalStrikes}'),
      );
    }

    if (detail.restrictedUntil != null &&
        detail.restrictedUntil!.isAfter(DateTime.now())) {
      rows.add(
        _InfoRow(
          label: 'Restriction ends',
          value: formatFullDate(detail.restrictedUntil!.toLocal()),
        ),
      );
    }

    if (detail.permanentlyDisabledAt != null) {
      rows.add(
        _InfoRow(
          label: 'Account action',
          value: detail.disableReason?.trim().isNotEmpty == true
              ? detail.disableReason!.trim()
              : 'Permanent disable applied',
        ),
      );
    }

    final explanation = detail.adminExplanation?.trim();
    if (explanation != null && explanation.isNotEmpty) {
      rows.add(_InfoRow(label: 'Admin note', value: explanation));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overview', style: AppTypography.subheading),
              const SizedBox(height: 12),
              ...rows,
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'This record reflects the latest decision on your account. '
          'Reporter identity and private evidence are not shown.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (detail.canAppeal && summary.reportId != null) ...[
          const SizedBox(height: 20),
          ThriftButton(
            label: 'Submit an appeal',
            onPressed: () => context.push(
              RouteNames.accountReviewFor(summary.reportId!),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
