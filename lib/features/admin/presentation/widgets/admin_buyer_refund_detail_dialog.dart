import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_buyer_refunds_controller.dart';
import '../../data/admin_refunds_service.dart';
import '../../data/delivery_payment_hold.dart';
import '../../domain/admin_buyer_refund.dart';
import 'admin_refund_panel.dart';
import 'admin_ui_components.dart';

/// Full refund actions for one buyer refund (manual GCash and legacy PayMongo status).
class AdminBuyerRefundDetailDialog extends StatefulWidget {
  const AdminBuyerRefundDetailDialog({
    super.key,
    required this.summary,
    required this.service,
  });

  final AdminBuyerRefundRow summary;
  final AdminRefundsService service;

  @override
  State<AdminBuyerRefundDetailDialog> createState() =>
      _AdminBuyerRefundDetailDialogState();
}

class _AdminBuyerRefundDetailDialogState
    extends State<AdminBuyerRefundDetailDialog> {
  DeliveryPaymentHold? _hold;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await widget.service.load(widget.summary.escrowId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hold = snapshot.hold;
        _error = snapshot.hold == null ? 'Refund record not found.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load refund details.';
      });
    }
  }

  void _onRefundChanged() {
    _load();
    context.read<AdminBuyerRefundsController>().load();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final width = MediaQuery.sizeOf(context).width;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 12 : 28,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.orderNumber, style: AppTypography.sectionTitle),
                        const SizedBox(height: 4),
                        Text(
                          s.buyerEmail == null || s.buyerEmail!.isEmpty
                              ? s.buyerName
                              : '${s.buyerName} · ${s.buyerEmail}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refund amount',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCentavos(s.amountCentavos),
                              style: AppTypography.heading.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AdminStatusBadge(
                            status: adminBuyerRefundBadgeKey(s.refundState),
                            label: adminRefundStateLabel(s.refundState),
                          ),
                          if (s.refundedAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              formatAdminTableDateTime(s.refundedAt!),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      Text(
                        _error!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
                        ),
                      )
                    else if (_hold != null) ...[
                      const _DialogSectionTitle(title: 'Actions & records'),
                      const SizedBox(height: 10),
                      AdminRefundPanel(
                        hold: _hold!,
                        onChanged: _onRefundChanged,
                        forDetailDialog: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.label.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}
