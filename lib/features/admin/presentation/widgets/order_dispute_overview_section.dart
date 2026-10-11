import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/order_model.dart';
import '../../../trust_safety/data/report_reasons.dart';
import 'admin_dispute_review_modal_shell.dart';
import 'admin_order_report_detail_widgets.dart';

/// Structured dispute context for the order dispute review modal.
class OrderDisputeOverviewSection extends StatelessWidget {
  const OrderDisputeOverviewSection({
    super.key,
    required this.report,
    required this.order,
    required this.parties,
  });

  final CommunityReportModel report;
  final OrderModel? order;
  final AdminOrderReportParties parties;

  @override
  Widget build(BuildContext context) {
    final reason = reportReasonLabel(report.category);
    final issue = report.details.trim();
    final orderRef = report.orderNumber?.trim();
    final product = order?.productTitle.trim();
    final orderStatus = order != null ? orderStatusLabel(order!.status) : null;

    return AdminDisputeModalSection(
      title: 'Dispute overview',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryBlock(
                reason: reason,
                issue: issue,
                submittedAt: report.createdAt,
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _PartiesBlock(parties: parties),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _OrderContextBlock(
                orderRef: orderRef?.isNotEmpty == true ? orderRef : null,
                product: product?.isNotEmpty == true ? product : null,
                orderStatus: orderStatus,
                buyerLine: '${parties.buyerName} · ${parties.buyerHandle}',
                sellerLine: _sellerLine(parties),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _sellerLine(AdminOrderReportParties parties) {
    final base = '${parties.sellerName} · ${parties.sellerHandle}';
    final shop = parties.sellerShop?.trim();
    if (shop != null && shop.isNotEmpty) return '$base · $shop';
    return base;
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.reason,
    required this.issue,
    required this.submittedAt,
  });

  final String reason;
  final String issue;
  final DateTime submittedAt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dispute reason',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 4),
            Text(
              reason,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
            ),
            if (issue.isNotEmpty) ...[
              SizedBox(height: 10),
              Text(
                'Reported issue',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                issue,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ],
        );

        final meta = Column(
          crossAxisAlignment: wide
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              'Reported',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 2),
            Text(
              formatAdminTableDateTime(submittedAt),
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [summary, const SizedBox(height: 12), meta],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            const SizedBox(width: 16),
            meta,
          ],
        );
      },
    );
  }
}

class _PartiesBlock extends StatelessWidget {
  const _PartiesBlock({required this.parties});

  final AdminOrderReportParties parties;

  @override
  Widget build(BuildContext context) {
    final reporterIsBuyer = parties.reporterRoleLabel == 'Buyer';
    final reportedRole = reporterIsBuyer ? 'Seller' : 'Buyer';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final reporter = _PartyTile(
          label: 'Reporter',
          role: parties.reporterRoleLabel,
          name: parties.reporterName,
          handle: parties.reporterHandle,
        );
        final reported = _PartyTile(
          label: 'Reported party',
          role: reportedRole,
          name: parties.reportedName,
          handle: parties.reportedHandle,
        );

        if (stack) {
          return Column(
            children: [reporter, const SizedBox(height: 12), reported],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: reporter),
              const SizedBox(width: 12),
              Expanded(child: reported),
            ],
          ),
        );
      },
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({
    required this.label,
    required this.role,
    required this.name,
    required this.handle,
  });

  final String label;
  final String role;
  final String name;
  final String handle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              _RoleBadge(role: role),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 2),
          Text(
            handle,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isBuyer = role == 'Buyer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isBuyer ? AppColors.primary : AppColors.textSecondary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role,
        style: AppTypography.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isBuyer ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OrderContextBlock extends StatelessWidget {
  const _OrderContextBlock({
    required this.orderRef,
    required this.product,
    required this.orderStatus,
    required this.buyerLine,
    required this.sellerLine,
  });

  final String? orderRef;
  final String? product;
  final String? orderStatus;
  final String buyerLine;
  final String sellerLine;

  @override
  Widget build(BuildContext context) {
    final headline = <String>[
      if (orderRef != null) 'Order $orderRef',
      if (product != null) product!,
      if (orderStatus != null) orderStatus!,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Affected order',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (headline.isNotEmpty)
          Text(
            headline,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.35,
            ),
          )
        else
          Text(
            'Order details are loading or unavailable.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        const SizedBox(height: 10),
        _CompactPartyLine(label: 'Buyer', value: buyerLine),
        const SizedBox(height: 6),
        _CompactPartyLine(label: 'Seller', value: sellerLine),
      ],
    );
  }
}

class _CompactPartyLine extends StatelessWidget {
  const _CompactPartyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.caption.copyWith(
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
