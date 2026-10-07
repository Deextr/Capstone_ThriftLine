import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/order_model.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../data/admin_review_rules.dart';
import '../../data/delivery_payment_hold.dart';
import 'admin_case_detail_widgets.dart';
import 'admin_review_widgets.dart';
import '../../../../widgets/skeleton_widgets.dart';
import 'admin_ui_components.dart';

/// Parties and roles for an order-linked community report.
class AdminOrderReportParties {
  const AdminOrderReportParties({
    required this.reporterName,
    required this.reporterHandle,
    required this.reporterRoleLabel,
    required this.buyerName,
    required this.buyerHandle,
    required this.sellerName,
    required this.sellerHandle,
    this.sellerShop,
    required this.reportedName,
    required this.reportedHandle,
  });

  final String reporterName;
  final String reporterHandle;
  final String reporterRoleLabel;
  final String buyerName;
  final String buyerHandle;
  final String sellerName;
  final String sellerHandle;
  final String? sellerShop;
  final String reportedName;
  final String reportedHandle;

  static AdminOrderReportParties from({
    required CommunityReportModel report,
    OrderModel? order,
  }) {
    final reporterIsBuyer = order != null
        ? report.reporterId == order.buyerId
        : report.reporterRole?.toLowerCase() == 'buyer';

    String nameForReporter() => report.reporterDisplayName;
    String handleForReporter() =>
        adminHandle(report.reporterUsername, report.reporterDisplayName);

    String buyerName;
    String buyerHandle;
    String sellerName;
    String sellerHandle;
    String? shop;

    if (order != null) {
      buyerName = order.buyerName.trim().isNotEmpty
          ? order.buyerName.trim()
          : (reporterIsBuyer ? nameForReporter() : report.reportedDisplayName);
      buyerHandle = reporterIsBuyer
          ? handleForReporter()
          : adminHandle(report.reportedUsername, report.reportedDisplayName);
      sellerName = order.sellerName.trim().isNotEmpty
          ? order.sellerName.trim()
          : (!reporterIsBuyer ? nameForReporter() : report.reportedDisplayName);
      sellerHandle = reporterIsBuyer
          ? adminHandle(report.reportedUsername, report.reportedDisplayName)
          : handleForReporter();
      shop = reporterIsBuyer
          ? (report.reportedShopName?.trim().isNotEmpty == true
                ? report.reportedShopName!.trim()
                : null)
          : null;
    } else {
      buyerName = reporterIsBuyer
          ? nameForReporter()
          : report.reportedDisplayName;
      buyerHandle = reporterIsBuyer
          ? handleForReporter()
          : adminHandle(report.reportedUsername, report.reportedDisplayName);
      sellerName = reporterIsBuyer
          ? report.reportedDisplayName
          : nameForReporter();
      sellerHandle = reporterIsBuyer
          ? adminHandle(report.reportedUsername, report.reportedDisplayName)
          : handleForReporter();
      shop = report.reportedShopName?.trim().isNotEmpty == true
          ? report.reportedShopName!.trim()
          : null;
    }

    return AdminOrderReportParties(
      reporterName: nameForReporter(),
      reporterHandle: handleForReporter(),
      reporterRoleLabel: reporterIsBuyer ? 'Buyer' : 'Seller',
      buyerName: buyerName,
      buyerHandle: buyerHandle,
      sellerName: sellerName,
      sellerHandle: sellerHandle,
      sellerShop: shop,
      reportedName: report.reportedDisplayName,
      reportedHandle: adminHandle(
        report.reportedUsername,
        report.reportedDisplayName,
      ),
    );
  }
}

class AdminOrderReportSectionCard extends StatelessWidget {
  const AdminOrderReportSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: AppTypography.subheading)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class AdminOrderReportSummaryCard extends StatelessWidget {
  const AdminOrderReportSummaryCard({
    super.key,
    required this.report,
    required this.parties,
    this.order,
    this.onOpenOrder,
  });

  final CommunityReportModel report;
  final AdminOrderReportParties parties;
  final OrderModel? order;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final reason = reportReasonLabel(report.category);
    final closed = !canDecideReport(report.status);
    final orderLabel = order != null
        ? '#${order!.orderNumber}'
        : (report.orderNumber != null ? '#${report.orderNumber}' : null);

    return AdminOrderReportSectionCard(
      title: 'Report summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminStatusBadge(
                status: report.status,
                label: reportStatusLabel(report.status),
              ),
              Text(
                reason,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${adminModerationCaseRef(report.id)} · Filed ${formatAdminTableDateTime(report.createdAt)}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final reporter = _SummaryPartyTile(
                label: 'Reporter',
                name: parties.reporterName,
                handle: parties.reporterHandle,
                chip: parties.reporterRoleLabel,
              );
              final reported = _SummaryPartyTile(
                label: 'Reported',
                name: parties.reportedName,
                handle: parties.reportedHandle,
                chip: 'Reported party',
                chipPrimary: true,
              );
              final orderTile = orderLabel != null
                  ? _SummaryOrderTile(label: orderLabel, onTap: onOpenOrder)
                  : const _SummaryPartyTile(
                      label: 'Order',
                      name: 'Unavailable',
                      handle: 'Order details could not be loaded',
                    );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: reporter),
                    const SizedBox(width: 16),
                    Expanded(child: reported),
                    const SizedBox(width: 16),
                    Expanded(child: orderTile),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  reporter,
                  const SizedBox(height: 14),
                  reported,
                  const SizedBox(height: 14),
                  orderTile,
                ],
              );
            },
          ),
          if (closed) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _ClosedOutcomeLine(report: report),
          ],
        ],
      ),
    );
  }
}

class _ClosedOutcomeLine extends StatelessWidget {
  const _ClosedOutcomeLine({required this.report});

  final CommunityReportModel report;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (report.resolutionFinancial?.isNotEmpty == true) {
      parts.add(orderReportFinancialLabel(report.resolutionFinancial!));
    }
    if (report.resolutionReturnRequired != null) {
      parts.add(
        report.resolutionReturnRequired!
            ? 'Return required'
            : 'No return required',
      );
    }
    if (report.resolvedAt != null) {
      parts.add('Closed ${formatAdminTableDateTime(report.resolvedAt!)}');
    }
    if (parts.isEmpty) {
      return Text(
        reportStatusLabel(report.status),
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }
    return Text(
      parts.join(' · '),
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        height: 1.4,
      ),
    );
  }
}

class _SummaryPartyTile extends StatelessWidget {
  const _SummaryPartyTile({
    required this.label,
    required this.name,
    required this.handle,
    this.chip,
    this.chipPrimary = false,
  });

  final String label;
  final String name;
  final String handle;
  final String? chip;
  final bool chipPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          handle,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (chip != null) ...[
          const SizedBox(height: 8),
          _RoleChip(label: chip!, primary: chipPrimary),
        ],
      ],
    );
  }
}

class _SummaryOrderTile extends StatelessWidget {
  const _SummaryOrderTile({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          )
        else
          Text(
            label,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: primary
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: primary
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: primary ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class AdminOrderReportDescriptionSection extends StatelessWidget {
  const AdminOrderReportDescriptionSection({super.key, required this.report});

  final CommunityReportModel report;

  @override
  Widget build(BuildContext context) {
    final details = report.details.trim();
    final instruction = report.reporterInstruction?.trim();
    final awaitingEvidence = report.status == kAdminReportNeedsEvidenceStatus;

    return AdminOrderReportSectionCard(
      title: 'Report description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (awaitingEvidence && instruction != null && instruction.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: 18,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Awaiting evidence',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    instruction,
                    style: AppTypography.body.copyWith(
                      height: 1.45,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (details.isEmpty)
            Text(
              'No description provided.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Text(
              details,
              style: AppTypography.body.copyWith(height: 1.55, fontSize: 14),
            ),
        ],
      ),
    );
  }
}

class AdminOrderReportOrderCard extends StatelessWidget {
  const AdminOrderReportOrderCard({
    super.key,
    required this.report,
    this.order,
    this.onOpenOrder,
    this.holdMissing = false,
    this.disputeId,
  });

  final CommunityReportModel report;
  final OrderModel? order;
  final VoidCallback? onOpenOrder;
  final bool holdMissing;
  final String? disputeId;

  @override
  Widget build(BuildContext context) {
    if (order == null) {
      return AdminOrderReportSectionCard(
        title: 'Order',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.orderNumber != null
                  ? 'Reference #${report.orderNumber}'
                  : 'Order unavailable',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
            if (report.orderTitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(report.orderTitle!.trim(), style: AppTypography.body),
            ],
            if (holdMissing && canDecideReport(report.status)) ...[
              const SizedBox(height: 12),
              AdminOrderReportMissingEscrowNotice(disputeId: disputeId),
            ],
          ],
        ),
      );
    }

    final o = order!;
    final shipment = o.shipment;

    return AdminOrderReportSectionCard(
      title: 'Order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: o.productImage.trim().isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: o.productImage.trim(),
                          fit: BoxFit.cover,
                          placeholder: (_, _) => ColoredBox(
                            color: AppColors.surfaceVariant,
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.textHint,
                            ),
                          ),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: AppColors.surfaceVariant,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textHint,
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textHint,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.productTitle,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Qty ${o.quantity} · ${formatCurrency(o.total)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminStatusBadge(
                status: o.status.name,
                label: orderStatusLabel(o.status),
              ),
              AdminStatusBadge(
                status: o.paymentStatus,
                label: _paymentLabel(o.paymentStatus),
              ),
              if (shipment != null)
                AdminStatusBadge(
                  status: shipment.deliveryStatus.name,
                  label: shipment.deliveryStatus.label,
                ),
            ],
          ),
          if (onOpenOrder != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenOrder,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open full order'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
          if (holdMissing && canDecideReport(report.status)) ...[
            const SizedBox(height: 8),
            AdminOrderReportMissingEscrowNotice(disputeId: disputeId),
          ],
        ],
      ),
    );
  }

  static String _paymentLabel(String raw) {
    final s = raw.trim().toLowerCase();
    return switch (s) {
      'paid' => 'Paid',
      'pending' => 'Payment pending',
      'refunded' => 'Refunded',
      'failed' => 'Payment failed',
      'expired' => 'Checkout expired',
      _ => raw.isEmpty ? 'Unknown' : raw,
    };
  }
}

class AdminOrderReportBuyerSellerSection extends StatelessWidget {
  const AdminOrderReportBuyerSellerSection({
    super.key,
    required this.parties,
    required this.report,
    this.order,
  });

  final AdminOrderReportParties parties;
  final CommunityReportModel report;
  final OrderModel? order;

  bool get _buyerIsReported {
    if (order != null) {
      return report.reportedUserId == order!.buyerId;
    }
    return report.reporterRole?.toLowerCase() == 'seller';
  }

  @override
  Widget build(BuildContext context) {
    final buyerLines = <String>[parties.buyerHandle];
    if (_buyerIsReported) buyerLines.add('Reported in this case');

    final sellerLines = <String>[parties.sellerHandle];
    if (parties.sellerShop?.trim().isNotEmpty == true) {
      sellerLines.add(parties.sellerShop!.trim());
    }
    if (!_buyerIsReported) sellerLines.add('Reported in this case');

    return AdminOrderReportSectionCard(
      title: 'Buyer & seller',
      child: AdminCasePartiesRow(
        leftTitle: 'Buyer',
        leftName: parties.buyerName,
        leftLines: buyerLines,
        rightTitle: 'Seller',
        rightName: parties.sellerName,
        rightLines: sellerLines,
      ),
    );
  }
}

class AdminOrderReportEvidenceSection extends StatelessWidget {
  const AdminOrderReportEvidenceSection({
    super.key,
    required this.report,
    required this.reporterRoleLabel,
  });

  final CommunityReportModel report;
  final String reporterRoleLabel;

  @override
  Widget build(BuildContext context) {
    final items = [...report.evidence]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final submissionLabel = '$reporterRoleLabel submission';

    return AdminOrderReportSectionCard(
      title: 'Evidence',
      trailing: report.evidenceAttemptCount > 1
          ? Text(
              'Round ${report.evidenceAttemptCount}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            submissionLabel,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty ||
              items.every((e) => (e.signedUrl ?? '').trim().isEmpty))
            Text(
              'No photos attached.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < items.length; i++)
                  if ((items[i].signedUrl ?? '').trim().isNotEmpty)
                    AdminPhotoThumb(
                      label: items.length == 1 ? 'Photo' : 'Photo ${i + 1}',
                      url: items[i].signedUrl!.trim(),
                      semanticLabel: 'Open evidence photo ${i + 1}',
                    ),
              ],
            ),
            if (report.evidenceAttemptCount > 1 && items.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Latest upload ${formatAdminTableDateTime(items.last.createdAt)}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class AdminOrderReportResolutionSection extends StatelessWidget {
  const AdminOrderReportResolutionSection({super.key, required this.report});

  final CommunityReportModel report;

  @override
  Widget build(BuildContext context) {
    final note = report.adminResponse?.trim();
    final financial = report.resolutionFinancial?.isNotEmpty == true
        ? orderReportFinancialLabel(report.resolutionFinancial!)
        : null;
    final returnLine = report.resolutionReturnRequired != null
        ? (report.resolutionReturnRequired!
              ? 'Return required'
              : 'No return required')
        : null;

    return AdminOrderReportSectionCard(
      title: 'Resolution',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (financial != null || returnLine != null)
            Text(
              [?financial, ?returnLine].join(' · '),
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
          if (report.resolvedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Closed ${formatAdminTableDateTime(report.resolvedAt!)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(note, style: AppTypography.body.copyWith(height: 1.5)),
          ] else if (financial == null) ...[
            const SizedBox(height: 4),
            Text(
              'No admin note was saved.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminOrderReportEscrowSummary extends StatelessWidget {
  const AdminOrderReportEscrowSummary({
    super.key,
    required this.hold,
    this.compact = false,
  });

  final DeliveryPaymentHold hold;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Escrow', deliveryHoldStatusLabel(hold.status)),
      ('Held amount', formatCentavos(hold.amountCentavos)),
      if (hold.isRefunded)
        ('Refund', refundProviderMessage(hold.refundProvider)),
    ];

    if (compact) {
      return Text(
        rows.map((r) => '${r.$1}: ${r.$2}').join(' · '),
        style: AppTypography.caption.copyWith(height: 1.45),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(row.$1, style: AppTypography.caption),
              ),
              Expanded(
                child: Text(
                  row.$2,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (deliveryHoldHint(hold.status).isNotEmpty)
          Text(
            deliveryHoldHint(hold.status),
            style: AppTypography.caption.copyWith(height: 1.4),
          ),
      ],
    );
  }
}

class AdminOrderReportMissingEscrowNotice extends StatelessWidget {
  const AdminOrderReportMissingEscrowNotice({super.key, this.disputeId});

  final String? disputeId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Escrow is not linked yet. Refund and release stay disabled until a delivery dispute holds this order\'s payment.',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (disputeId != null && disputeId!.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () =>
                context.push(RouteNames.adminDisputeDetailFor(disputeId!)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Open linked dispute'),
          ),
        ],
      ],
    );
  }
}

class AdminOrderReportReferences extends StatelessWidget {
  const AdminOrderReportReferences({
    super.key,
    required this.report,
    this.escrowId,
  });

  final CommunityReportModel report;
  final String? escrowId;

  @override
  Widget build(BuildContext context) {
    return AdminOrderReportSectionCard(
      title: 'References',
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            'Internal IDs',
            style: AppTypography.body.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          children: [
            _refRow('Report', report.id),
            if (report.orderId?.isNotEmpty == true)
              _refRow('Order', report.orderId!),
            if (report.disputeId?.isNotEmpty == true)
              _refRow('Dispute', report.disputeId!),
            if (escrowId != null && escrowId!.isNotEmpty)
              _refRow('Escrow', escrowId!),
          ],
        ),
      ),
    );
  }

  Widget _refRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: AppTypography.caption)),
          Expanded(
            child: SelectableText(
              value,
              style: AppTypography.caption.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminOrderReportEscrowStrip extends StatelessWidget {
  const AdminOrderReportEscrowStrip({super.key, required this.hold});

  final DeliveryPaymentHold hold;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdminStatusBadge(
          status: hold.status,
          label: deliveryHoldStatusLabel(hold.status),
        ),
        Text(
          formatCentavos(hold.amountCentavos),
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'held for this order',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class AdminOrderReportDecisionSection extends StatelessWidget {
  const AdminOrderReportDecisionSection({
    super.key,
    required this.holdMissing,
    this.disputeId,
    this.hold,
    this.panel,
  });

  final bool holdMissing;
  final String? disputeId;
  final DeliveryPaymentHold? hold;
  final Widget? panel;

  @override
  Widget build(BuildContext context) {
    return AdminOrderReportSectionCard(
      title: 'Decision',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hold != null) ...[
            AdminOrderReportEscrowStrip(hold: hold!),
            const SizedBox(height: 16),
          ],
          if (holdMissing || panel == null)
            AdminOrderReportMissingEscrowNotice(disputeId: disputeId)
          else
            panel!,
        ],
      ),
    );
  }
}

class AdminOrderReportMainColumn extends StatelessWidget {
  const AdminOrderReportMainColumn({
    super.key,
    required this.report,
    required this.order,
    required this.parties,
    required this.timelineEvents,
    required this.canDecide,
    required this.holdMissing,
    this.hold,
    this.onOpenOrder,
    this.escrowId,
    this.decisionSection,
  });

  final CommunityReportModel report;
  final OrderModel? order;
  final AdminOrderReportParties parties;
  final List<AdminCaseTimelineEvent> timelineEvents;
  final bool canDecide;
  final bool holdMissing;
  final DeliveryPaymentHold? hold;
  final VoidCallback? onOpenOrder;
  final String? escrowId;
  final Widget? decisionSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminOrderReportSummaryCard(
          report: report,
          parties: parties,
          order: order,
          onOpenOrder: onOpenOrder,
        ),
        const SizedBox(height: 16),
        AdminOrderReportDescriptionSection(report: report),
        const SizedBox(height: 16),
        AdminOrderReportOrderCard(
          report: report,
          order: order,
          onOpenOrder: onOpenOrder,
          holdMissing: false,
          disputeId: report.disputeId,
        ),
        const SizedBox(height: 16),
        AdminOrderReportEvidenceSection(
          report: report,
          reporterRoleLabel: parties.reporterRoleLabel,
        ),
        const SizedBox(height: 16),
        AdminOrderReportSectionCard(
          title: 'Case history',
          child: AdminCaseTimeline(events: timelineEvents),
        ),
        if (decisionSection != null) ...[
          const SizedBox(height: 16),
          decisionSection!,
        ] else if (hold != null && !canDecide) ...[
          const SizedBox(height: 16),
          AdminOrderReportSectionCard(
            title: 'Payment',
            child: AdminOrderReportEscrowStrip(hold: hold!),
          ),
        ],
        if (!canDecide) ...[
          const SizedBox(height: 16),
          AdminOrderReportResolutionSection(report: report),
        ],
        const SizedBox(height: 16),
        AdminOrderReportReferences(report: report, escrowId: escrowId),
      ],
    );
  }
}

class AdminWideCaseDetailSkeleton extends StatelessWidget {
  const AdminWideCaseDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            const ShimmerBox(width: 160, height: 20, radius: 20),
            const SizedBox(height: 20),
            const ShimmerBox(width: double.infinity, height: 160, radius: 12),
            const SizedBox(height: 16),
            const ShimmerBox(width: double.infinity, height: 100, radius: 12),
            const SizedBox(height: 16),
            const ShimmerBox(width: double.infinity, height: 120, radius: 12),
          ],
        );
      },
    );
  }
}
