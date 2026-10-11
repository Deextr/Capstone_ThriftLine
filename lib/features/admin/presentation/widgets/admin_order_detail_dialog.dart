import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';
import '../../data/admin_orders_service.dart';
import '../../data/delivery_payment_hold.dart';
import '../../domain/admin_order_management.dart';
import 'admin_review_widgets.dart';
import 'admin_ui_components.dart';

class _CloseDialogIntent extends Intent {
  const _CloseDialogIntent();
}

Future<void> showAdminOrderDetailDialog({
  required BuildContext context,
  required AdminOrderRow summary,
  required Future<AdminOrderDetailBundle?> Function() loadDetail,
  void Function(String siblingOrderId)? onOpenSiblingOrder,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return _AdminOrderDetailDialog(
        summary: summary,
        loadDetail: loadDetail,
        onOpenSiblingOrder: onOpenSiblingOrder,
      );
    },
  );
}

class _AdminOrderDetailDialog extends StatefulWidget {
  const _AdminOrderDetailDialog({
    required this.summary,
    required this.loadDetail,
    this.onOpenSiblingOrder,
  });

  final AdminOrderRow summary;
  final Future<AdminOrderDetailBundle?> Function() loadDetail;
  final void Function(String siblingOrderId)? onOpenSiblingOrder;

  @override
  State<_AdminOrderDetailDialog> createState() =>
      _AdminOrderDetailDialogState();
}

class _AdminOrderDetailDialogState extends State<_AdminOrderDetailDialog> {
  AdminOrderDetailBundle? _detail;
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
    final bundle = await widget.loadDetail();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = bundle;
      _error = bundle == null ? 'Unable to load order details.' : null;
    });
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width < 720
        ? width - 32
        : (width > 960 ? 720.0 : width * 0.9).clamp(320.0, 720.0);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _CloseDialogIntent(),
      },
      child: Actions(
        actions: {
          _CloseDialogIntent: CallbackAction<_CloseDialogIntent>(
            onInvoke: (_) {
              _close();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: AppColors.surface,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OrderModalHeader(
                    summary: widget.summary,
                    detail: _detail,
                    onClose: _close,
                  ),
                  Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? _ErrorBody(message: _error!, onRetry: _load)
                        : _OrderModalBody(
                            detail: _detail!,
                            onOpenSiblingOrder: widget.onOpenSiblingOrder,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderModalHeader extends StatelessWidget {
  const _OrderModalHeader({
    required this.summary,
    required this.detail,
    required this.onClose,
  });

  final AdminOrderRow summary;
  final AdminOrderDetailBundle? detail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final order = detail?.order;
    final reference = (order?.orderNumber ?? summary.orderNumber).trim();
    final displayRef = reference.isNotEmpty ? reference : 'Order';
    final createdAt = order?.createdAt ?? summary.createdAt;
    final kind = detail?.orderKind ?? summary.orderKind;
    final unified = detail?.unifiedStatus ?? summary.unifiedStatus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayRef,
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AdminOrderTypeBadge(label: adminOrderKindLabel(kind)),
                    AdminStatusBadge(
                      status: unified.badgeKey,
                      label: unified.label,
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  '${formatAdminPhilippinesDate(createdAt)} · ${formatAdminPhilippinesTime(createdAt)} PHT',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close (Esc)',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _OrderModalBody extends StatelessWidget {
  const _OrderModalBody({required this.detail, this.onOpenSiblingOrder});

  final AdminOrderDetailBundle detail;
  final void Function(String siblingOrderId)? onOpenSiblingOrder;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final events = buildAdminOrderTimeline(
      payments: detail.payments,
      escrow: detail.escrowRow,
    );
    final hasFulfillment = _hasFulfillmentContent(order);
    final hasDisputesEscrow =
        detail.reports.isNotEmpty ||
        (detail.escrow != null && detail.escrow!.escrowId.isNotEmpty);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (detail.loadWarnings.isNotEmpty) ...[
            Text(
              detail.loadWarnings.join(' '),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ModalSection(
            title: 'Order summary',
            child: _OrderSummaryBlock(
              detail: detail,
              onOpenSibling: onOpenSiblingOrder,
            ),
          ),
          _sectionGap(),
          _ModalSection(
            title: 'Ordered items',
            child: _LineItemsList(items: order.items),
          ),
          _sectionGap(),
          _ModalSection(
            title: 'Buyer & seller',
            child: _PartiesRow(detail: detail),
          ),
          _sectionGap(),
          _ModalSection(
            title: 'Payment breakdown',
            child: _PaymentBreakdownBlock(detail: detail),
          ),
          if (hasFulfillment) ...[
            _sectionGap(),
            _ModalSection(
              title: 'Fulfillment & delivery',
              child: _FulfillmentBlock(order: order),
            ),
          ],
          if (events.isNotEmpty) ...[
            _sectionGap(),
            _ModalSection(
              title: 'Transaction history',
              child: _CompactTimeline(events: events),
            ),
          ],
          if (hasDisputesEscrow) ...[
            _sectionGap(),
            _ModalSection(
              title: 'Disputes & escrow',
              child: _DisputesEscrowBlock(detail: detail),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasFulfillmentContent(OrderModel order) {
    if (order.shipment != null) return true;
    if (order.trackingNumber?.trim().isNotEmpty == true) return true;
    if (order.courier?.trim().isNotEmpty == true) return true;
    final status = adminOrderFulfillmentLabel(order);
    return status != 'Awaiting payment' && status != 'Unknown';
  }

  Widget _sectionGap() => const SizedBox(height: 20);
}

class _ModalSection extends StatelessWidget {
  const _ModalSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTypography.label.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _OrderSummaryBlock extends StatelessWidget {
  const _OrderSummaryBlock({required this.detail, this.onOpenSibling});

  final AdminOrderDetailBundle detail;
  final void Function(String orderId)? onOpenSibling;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final payment = detail.primaryPayment;
    final method = payment != null
        ? adminPaymongoChannelLabel(payment['paymongo_channel'] as String?)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buyer total (this seller)',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    formatCurrency(order.total),
                    style: AppTypography.heading.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Payment',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  adminPaymentStatusLabel(order.paymentStatus),
                  style: AppTypography.tableBodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (method != null)
                  Text(
                    method,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
        SizedBox(height: 10),
        Text(
          'Fulfillment: ${adminOrderFulfillmentLabel(order)}',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (detail.orderKind == AdminOrderKind.auction) ...[
          const SizedBox(height: 10),
          _AuctionSummaryLines(order: order),
        ],
        if (detail.siblings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MultiSellerInlineNotice(
            siblings: detail.siblings,
            onOpenSibling: onOpenSibling,
          ),
        ],
      ],
    );
  }
}

class _AuctionSummaryLines extends StatelessWidget {
  const _AuctionSummaryLines({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (order.amount > 0) {
      lines.add('Winning amount ${formatCurrency(order.amount)}');
    }
    if (order.paymentDueAt != null) {
      lines.add(
        'Payment due ${formatAdminPhilippinesDate(order.paymentDueAt!)} · '
        '${formatAdminPhilippinesTime(order.paymentDueAt!)} PHT',
      );
    }
    if (order.isAuctionObligation && order.showsAsAwaitingPayment) {
      lines.add('Winner payment window open');
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Auction',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4),
        for (final line in lines)
          Text(
            line,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _MultiSellerInlineNotice extends StatelessWidget {
  const _MultiSellerInlineNotice({required this.siblings, this.onOpenSibling});

  final List<AdminCheckoutSiblingSummary> siblings;
  final void Function(String orderId)? onOpenSibling;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Multi-seller checkout — amounts below are for this seller only.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          if (onOpenSibling != null && siblings.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final s in siblings)
              TextButton(
                onPressed: () => onOpenSibling!(s.orderId),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.primary,
                ),
                child: Text(
                  'View ${s.orderNumber.isNotEmpty ? s.orderNumber : 'related order'} · ${s.sellerName}',
                  style: AppTypography.caption,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PartiesRow extends StatelessWidget {
  const _PartiesRow({required this.detail});

  final AdminOrderDetailBundle detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 420;
        final buyer = _PartyColumn(
          title: 'Buyer',
          name: order.buyerName,
          subtitle: detail.buyerUsername?.trim().isNotEmpty == true
              ? '@${detail.buyerUsername!.trim()}'
              : null,
        );
        final seller = _PartyColumn(
          title: 'Seller',
          name: order.sellerName,
          subtitle: _sellerSubtitle(detail),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [buyer, const SizedBox(height: 12), seller],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: buyer),
            const SizedBox(width: 24),
            Expanded(child: seller),
          ],
        );
      },
    );
  }

  String? _sellerSubtitle(AdminOrderDetailBundle detail) {
    final shop = detail.sellerShopName?.trim();
    final user = detail.sellerUsername?.trim();
    if (shop != null && shop.isNotEmpty) return shop;
    if (user != null && user.isNotEmpty) return '@$user';
    return null;
  }
}

class _PartyColumn extends StatelessWidget {
  const _PartyColumn({required this.title, required this.name, this.subtitle});

  final String title;
  final String name;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4),
        Text(name, style: AppTypography.tableBodyMedium),
        if (subtitle != null)
          Text(
            subtitle!,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _LineItemsList extends StatelessWidget {
  const _LineItemsList({required this.items});

  final List<OrderLineItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'No line items on record.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppColors.border),
            ),
          _LineItemRow(item: items[i]),
        ],
      ],
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item});

  final OrderLineItem item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item.imageUrl ?? '').trim();
    final hasImage = imageUrl.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LineItemThumbnail(
          imageUrl: hasImage ? imageUrl : null,
          onTap: hasImage
              ? () => showAdminImagePreview(context, imageUrl)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: AppTypography.tableBodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2),
              Text(
                'Qty ${item.quantity} × ${formatCurrency(item.unitPrice)}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatCurrency(item.lineTotal),
          style: AppTypography.tableBodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ItemImagePlaceholder extends StatelessWidget {
  const _ItemImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(Icons.image_outlined, size: 20, color: AppColors.textHint),
      ),
    );
  }
}

class _LineItemThumbnail extends StatelessWidget {
  const _LineItemThumbnail({this.imageUrl, this.onTap});

  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 52,
        height: 52,
        child: imageUrl != null
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const _ItemImagePlaceholder(),
              )
            : const _ItemImagePlaceholder(),
      ),
    );

    if (onTap == null) return child;

    return Semantics(
      button: true,
      label: 'View product image',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PaymentBreakdownBlock extends StatelessWidget {
  const _PaymentBreakdownBlock({required this.detail});

  final AdminOrderDetailBundle detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final payment = detail.primaryPayment;
    final allocationCentavos = payment?['amount_centavos'] as num?;
    final ref = payment != null ? _shortPaymongoRef(payment) : null;
    final hold = detail.escrow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KVRow(label: 'Items subtotal', value: formatCurrency(order.amount)),
        _KVRow(label: 'Shipping fee', value: formatCurrency(order.shippingFee)),
        _KVRow(
          label: 'Platform fee',
          value: formatCurrency(order.platformFee),
          valueColor: AppColors.primary,
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: AppColors.border),
        ),
        _KVRow(
          label: 'Buyer total (this seller order)',
          value: formatCurrency(order.total),
          emphasize: true,
        ),
        _KVRow(
          label: 'Seller allocation',
          value: formatCurrency(detail.sellerAllocation),
        ),
        if (payment != null &&
            allocationCentavos != null &&
            allocationCentavos.round() > 0)
          _KVRow(
            label: 'PayMongo allocation',
            value: formatCentavos(allocationCentavos.round()),
          ),
        const SizedBox(height: 8),
        _KVRow(
          label: 'Payment status',
          value: adminPaymentStatusLabel(order.paymentStatus),
        ),
        if (hold != null && hold.escrowId.isNotEmpty)
          _KVRow(
            label: 'Escrow status',
            value: deliveryHoldStatusLabel(hold.status),
          ),
        if (order.paymentStatus == 'refunded' ||
            (hold != null && hold.isRefunded))
          _KVRow(label: 'Refund', value: 'Recorded'),
        if (ref != null) _KVRow(label: 'Provider reference', value: ref),
      ],
    );
  }

  String? _shortPaymongoRef(Map<String, dynamic> payment) {
    final raw = payment['paymongo_payment_id']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.length <= 16) return raw;
    return '${raw.substring(0, 16)}…';
  }
}

class _FulfillmentBlock extends StatelessWidget {
  const _FulfillmentBlock({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final shipment = order.shipment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KVRow(label: 'Status', value: adminOrderFulfillmentLabel(order)),
        if (shipment != null)
          _KVRow(
            label: 'Delivery method',
            value: shipment.isLocalRider ? 'Local rider' : 'Official courier',
          ),
        if (order.trackingNumber?.trim().isNotEmpty == true)
          _KVRow(label: 'Tracking', value: order.trackingNumber!.trim()),
        if (order.courier?.trim().isNotEmpty == true)
          _KVRow(label: 'Courier', value: order.courier!.trim()),
        if (shipment?.estimatedDeliveryAt != null)
          _KVRow(
            label: 'Estimated delivery',
            value:
                '${formatAdminPhilippinesDate(shipment!.estimatedDeliveryAt!)} · '
                '${formatAdminPhilippinesTime(shipment.estimatedDeliveryAt!)} PHT',
          ),
      ],
    );
  }
}

class _CompactTimeline extends StatelessWidget {
  const _CompactTimeline({required this.events});

  final List<AdminOrderTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineRow(event: events[i], isLast: i == events.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final AdminOrderTimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: AppTypography.tableBody),
                  if (event.detail?.trim().isNotEmpty == true)
                    Text(
                      event.detail!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Text(
                    '${formatAdminPhilippinesDate(event.at)} · '
                    '${formatAdminPhilippinesTime(event.at)} PHT',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisputesEscrowBlock extends StatelessWidget {
  const _DisputesEscrowBlock({required this.detail});

  final AdminOrderDetailBundle detail;

  @override
  Widget build(BuildContext context) {
    final hold = detail.escrow;
    final hasEscrow = hold != null && hold.escrowId.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasEscrow) ...[
          Row(
            children: [
              AdminStatusBadge(
                status: hold.status,
                label: deliveryHoldStatusLabel(hold.status),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            deliveryHoldHint(hold.status),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          _KVRow(
            label: 'Held amount',
            value: formatCentavos(hold.amountCentavos),
          ),
          _KVRow(
            label: 'Seller portion',
            value: formatCentavos(hold.sellerAmountCentavos),
          ),
          if (hold.isRefunded && hold.refundProvider.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              refundProviderMessage(hold.refundProvider),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
        if (detail.reports.isNotEmpty) ...[
          if (hasEscrow) const SizedBox(height: 14),
          for (var i = 0; i < detail.reports.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.reports[i].reason.isNotEmpty
                            ? detail.reports[i].reason
                            : 'Order report',
                        style: AppTypography.tableBody,
                      ),
                      Text(
                        formatAdminPhilippinesDate(detail.reports[i].createdAt),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusBadge(status: detail.reports[i].status),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _KVRow extends StatelessWidget {
  const _KVRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (emphasize
                          ? AppTypography.tableBodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            )
                          : AppTypography.tableBody)
                      .copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
