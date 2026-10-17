import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/supabase_service.dart';
import '../../controllers/admin_buyer_refunds_controller.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../../data/admin_orders_service.dart';
import '../../data/admin_refunds_service.dart';
import '../../domain/admin_buyer_refund.dart';
import 'admin_buyer_refund_detail_dialog.dart';

AdminBuyerRefundRow buyerRefundRowFromOrderDetail(
  AdminOrderDetailBundle detail,
) {
  final hold = detail.escrow!;
  final order = detail.order;
  return AdminBuyerRefundRow(
    escrowId: hold.escrowId,
    orderId: order.id,
    orderNumber: order.orderNumber,
    buyerId: hold.buyerId ?? order.buyerId,
    buyerName: order.buyerName,
    amountCentavos: hold.amountCentavos,
    refundState: hold.refundState ?? '',
    refundProviderStatus: hold.refundProviderStatus,
    refundLocked: hold.refundLocked,
    refundedAt: hold.refundCompletedAt,
    paymongoRefundId: hold.paymongoRefundId,
  );
}

/// Opens the Buyer Refunds detail modal after closing the order modal.
Future<void> openBuyerRefundDetailFromOrder({
  required BuildContext hostContext,
  required AdminOrderDetailBundle detail,
  VoidCallback? closeOrderModal,
}) async {
  final hold = detail.escrow;
  if (hold == null || hold.escrowId.isEmpty || !hold.isRefunded) return;

  closeOrderModal?.call();
  await Future<void>.delayed(Duration.zero);
  if (!hostContext.mounted) return;

  final summary = buyerRefundRowFromOrderDetail(detail);
  await showDialog<void>(
    context: hostContext,
    builder: (dialogContext) => ChangeNotifierProvider(
      create: (ctx) => AdminBuyerRefundsController(
        supabase: ctx.read<SupabaseService>(),
        onNeedsActionCountChanged: ctx
            .read<AdminDashboardController>()
            .setPendingBuyerRefundCount,
      ),
      child: AdminBuyerRefundDetailDialog(
        summary: summary,
        service: AdminRefundsService(hostContext.read<SupabaseService>()),
      ),
    ),
  );
}
