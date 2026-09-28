import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/address_model.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../profile/data/address_service.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../../data/paymongo_checkout.dart';
import '../widgets/pay_now_button.dart';
import '../widgets/payment_deadline_text.dart';

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  var _didOpenPaidConfirmation = false;
  var _didHandleReturn = false;
  String? _selectedChannel;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    if (controller.isLoading && controller.order == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final order = controller.order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Payment'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(RouteNames.cart),
          ),
        ),
        body: Center(child: Text(controller.errorMessage ?? 'Order not found')),
      );
    }

    final pending = order.isPaymentPending;
    final returnUri = GoRouterState.of(context).uri;
    final returned = returnUri.queryParameters['returned'] == '1';
    final returnStatus = (returnUri.queryParameters['status'] ?? '')
        .trim()
        .toLowerCase();
    final cancelledReturn =
        returnStatus == 'cancel' || returnStatus == 'cancelled';
    final failed = order.isFailedCheckout || controller.isExpiredPayment;
    _scheduleReturnHandling(returned, cancelledReturn);
    final confirming = pending && !failed && controller.isConfirmingPayment;
    _schedulePaidConfirmation(pending, failed);

    return PopScope(
      canPop: !pending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !pending) return;
        _leavePendingCheckout(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            failed
                ? (controller.isExpiredPayment
                      ? 'Payment Expired'
                      : 'Payment Failed')
                : pending
                ? 'Payment'
                : 'Payment Successful',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (pending) {
                _leavePendingCheckout(controller);
                return;
              }
              if (failed) {
                context.go(RouteNames.cart);
                return;
              }
              context.go(RouteNames.orderConfirmFor(widget.orderId));
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: failed
                ? _FailedPaymentBody(
                    channel: _selectedChannel,
                    expired: controller.isExpiredPayment,
<<<<<<< HEAD
                    onReturnToCart: () async {
                      await context.read<CartProvider>().refresh();
                      if (context.mounted) {
                        context.go(RouteNames.checkout);
                      }
                    },
                    onTryAgain: () async {
                      await context.read<CartProvider>().refresh();
                      if (context.mounted) {
                        context.go(RouteNames.checkout);
                      }
                    },
=======
                    onReturnToCart: () => context.go(RouteNames.cart),
                    onTryAgain: () => context.go(RouteNames.cart),
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                  )
                : pending
                ? _PendingPaymentBody(
                    order: order,
                    sellerName: order.sellerName,
                    itemLabel: order.items.length > 1
                        ? '${order.items.length} items from ${order.sellerName}'
                        : order.productTitle,
                    totalLabel: formatCurrency(order.total),
                    paymentDueAt: order.paymentDueAt,
                    windowOpen: order.isPaymentWindowOpen,
                    confirming: confirming,
                    selectedChannel: _selectedChannel,
                    isAbandoning: controller.isAbandoning,
                    isSavingAddress: controller.isSavingAddress,
                    returnLabel: (order.auctionId ?? '').isNotEmpty
                        ? 'Cancel payment'
                        : 'Return to Cart',
                    onSelectChannel: (channel) {
                      setState(() => _selectedChannel = channel);
                    },
                    onChangeMethod: () {
                      setState(() => _selectedChannel = null);
                    },
                    onChangeAddress: () => _changeAddress(controller),
                    onReturnToCart: confirming
                        ? null
                        : () => unawaited(_returnToCart(controller)),
                  )
                : _PaidPaymentBody(
                    orderNumber: order.orderNumber,
                    channel: _selectedChannel,
                    onViewOrder: () =>
                        context.go(RouteNames.orderConfirmFor(widget.orderId)),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _leavePendingCheckout(BuyerOrdersController controller) async {
    final isAuction = (controller.order?.auctionId ?? '').isNotEmpty;
    if (isAuction) {
      context.go(RouteNames.buyerHome);
      return;
    }

    final cancelAndReturn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave checkout?'),
        content: const Text(
          'Do you want to cancel this checkout and return items to your cart, or keep it pending?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep pending'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Return to cart'),
          ),
        ],
      ),
    );

    if (!mounted || cancelAndReturn == null) return;
    if (cancelAndReturn) {
      await _returnToCart(controller);
    } else {
      context.go(RouteNames.buyerHome);
    }
  }

  Future<void> _changeAddress(BuyerOrdersController controller) async {
    final result = await context.push<dynamic>(RouteNames.addresses);
    if (!mounted) return;

    String? newAddressId;
    if (result is AddressModel) {
      newAddressId = result.id;
    } else {
      final supabase = context.read<SupabaseService>();
      final def = await AddressService(supabase).defaultAddress();
      newAddressId = def?.id;
    }

    if (newAddressId != null && newAddressId.isNotEmpty) {
      final error = await controller.setAddress(newAddressId);
      if (!mounted) return;
      if (error != null) {
        showThriftSnackBar(context, error, isError: true);
      } else {
        showThriftSnackBar(context, 'Delivery address updated.');
      }
    }
  }

  Future<void> _returnToCart(BuyerOrdersController controller) async {
    final isAuction = (controller.order?.auctionId ?? '').isNotEmpty;
    final error = await controller.abandonUnpaidCheckout(widget.orderId);
    if (!mounted) return;
    if (!isAuction) {
      await context.read<CartProvider>().refresh();
      if (!mounted) return;
    }
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
    } else {
      showThriftSnackBar(context, 'Checkout cancelled. Items returned to your cart.');
    }
    context.go(isAuction ? RouteNames.buyerHome : RouteNames.cart);
  }

  void _scheduleReturnHandling(bool returned, bool cancelled) {
    if (!returned || _didHandleReturn) return;
    _didHandleReturn = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<BuyerOrdersController>();
      if (cancelled) {
        final isAuction = (controller.order?.auctionId ?? '').isNotEmpty;
        await controller.abandonUnpaidCheckout(widget.orderId);
        if (!mounted) return;
        if (!isAuction) {
          await context.read<CartProvider>().refresh();
          if (!mounted) return;
        }
        showThriftSnackBar(
          context,
          'Checkout cancelled. Items returned to your cart.',
        );
        context.go(isAuction ? RouteNames.buyerHome : RouteNames.checkout);
        return;
      }
      unawaited(
        controller.handlePaymongoAppReturn(cancelled: false),
      );
    });
  }

  void _schedulePaidConfirmation(bool pending, bool failed) {
    if (pending || failed || _didOpenPaidConfirmation) return;
    _didOpenPaidConfirmation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(RouteNames.orderConfirmFor(widget.orderId));
    });
  }
}

class _PendingPaymentBody extends StatelessWidget {
  const _PendingPaymentBody({
    required this.order,
    required this.sellerName,
    required this.itemLabel,
    required this.totalLabel,
    this.paymentDueAt,
    this.windowOpen = true,
    required this.confirming,
    required this.selectedChannel,
    required this.isAbandoning,
    required this.isSavingAddress,
    required this.returnLabel,
    required this.onSelectChannel,
    required this.onChangeMethod,
    required this.onChangeAddress,
    this.onReturnToCart,
  });

  final OrderModel order;
  final String sellerName;
  final String itemLabel;
  final String totalLabel;
  final DateTime? paymentDueAt;
  final bool windowOpen;
  final bool confirming;
  final String? selectedChannel;
  final bool isAbandoning;
  final bool isSavingAddress;
  final String returnLabel;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback onChangeMethod;
  final VoidCallback onChangeAddress;
  final VoidCallback? onReturnToCart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
<<<<<<< HEAD
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  confirming
                      ? 'Confirming payment…'
                      : selectedChannel == null
                      ? 'Payment Method'
                      : paymongoChannelLabel(selectedChannel!),
                  style: AppTypography.heading,
                ),
                const SizedBox(height: 8),
                Text(
                  confirming
                      ? 'PayMongo is confirming this payment. ThriftLine will update only after the verified webhook arrives.'
                      : selectedChannel == null
                      ? 'Choose how you want to pay. Payment is required to complete this purchase.'
                      : 'Pay securely through PayMongo',
                  style: AppTypography.body,
                ),
                const SizedBox(height: 16),
                _PaymentAddressCard(
                  order: order,
                  isSavingAddress: isSavingAddress,
                  onChangeAddress: onChangeAddress,
                ),
                const SizedBox(height: 12),
                ThriftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(itemLabel, style: AppTypography.subheading),
                      Text('Seller: $sellerName', style: AppTypography.caption),
                      const Divider(),
                      _PaymentRow(label: 'Amount to Pay', value: totalLabel),
                      _PaymentRow(
                        label: 'Status',
                        value: confirming ? 'Confirming payment…' : 'Payment required',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (confirming)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (selectedChannel == null)
                  _MethodPicker(onSelect: onSelectChannel),
              ],
            ),
=======
        Text(
          confirming
              ? 'Confirming payment…'
              : selectedChannel == null
              ? 'Payment Method'
              : paymongoChannelLabel(selectedChannel!),
          style: AppTypography.heading,
        ),
        const SizedBox(height: 8),
        Text(
          confirming
              ? 'PayMongo is confirming this payment. ThriftLine will update only after the verified webhook arrives.'
              : selectedChannel == null
              ? 'Choose how you want to pay. Payment is required to complete this purchase.'
              : 'Pay securely through PayMongo',
          style: AppTypography.body,
        ),
        const SizedBox(height: 16),
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(itemLabel, style: AppTypography.subheading),
              Text('Seller: $sellerName', style: AppTypography.caption),
              const Divider(),
              _PaymentRow(label: 'Amount to Pay', value: totalLabel),
              _PaymentRow(
                label: 'Status',
                value: confirming
                    ? 'Confirming payment…'
                    : windowOpen
                    ? 'Unpaid'
                    : 'Payment window ended',
              ),
              if (paymentDueAt != null) ...[
                const SizedBox(height: 8),
                PaymentDeadlineText(due: paymentDueAt!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (confirming)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (selectedChannel == null)
          Expanded(child: _MethodPicker(onSelect: onSelectChannel))
        else
          const Spacer(),
        if (!confirming && selectedChannel != null && windowOpen) ...[
          PayNowButton(
            orderId: orderId,
            channel: selectedChannel!,
            amountLabel: totalLabel,
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
          ),
        ),
        if (!confirming && selectedChannel != null) ...[
          const SizedBox(height: 12),
          if (order.addressMissing || order.shippingAddress.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThriftButton(
                label: 'Add delivery address to pay',
                variant: ThriftButtonVariant.primary,
                onPressed: onChangeAddress,
              ),
            )
          else
            PayNowButton(
              orderId: order.id,
              channel: selectedChannel!,
              amountLabel: totalLabel,
            ),
          const SizedBox(height: 12),
          ThriftButton(
            label: 'Change method',
            variant: ThriftButtonVariant.outline,
            onPressed: onChangeMethod,
          ),
          const SizedBox(height: 12),
        ],
        if (onReturnToCart != null)
          ThriftButton(
            label: isAbandoning ? 'Cancelling…' : returnLabel,
            variant: ThriftButtonVariant.outline,
            onPressed: isAbandoning ? null : onReturnToCart,
          ),
      ],
    );
  }
}

class _PaymentAddressCard extends StatelessWidget {
  const _PaymentAddressCard({
    required this.order,
    required this.isSavingAddress,
    required this.onChangeAddress,
  });

  final OrderModel order;
  final bool isSavingAddress;
  final VoidCallback onChangeAddress;

  @override
  Widget build(BuildContext context) {
    final addressText = order.shippingAddress.trim();
    final hasAddress = !order.addressMissing && addressText.isNotEmpty;

    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery Address',
                  style: AppTypography.subheading,
                ),
              ),
              if (isSavingAddress)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                TextButton(
                  onPressed: onChangeAddress,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(hasAddress ? 'Change' : 'Add'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasAddress) ...[
            Text(
              order.buyerName.isNotEmpty ? order.buyerName : 'Recipient',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              addressText,
              style: AppTypography.body.copyWith(fontSize: 13),
            ),
          ] else ...[
            Text(
              'No delivery address specified. Please add an address to complete your order.',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cards', style: AppTypography.caption),
        const SizedBox(height: 8),
        _MethodTile(
          label: 'Credit / Debit Card',
          icon: Icons.credit_card_rounded,
          onTap: () => onSelect('card'),
        ),
        const SizedBox(height: 20),
        Text('E-Wallets', style: AppTypography.caption),
        const SizedBox(height: 8),
        _MethodTile(
          label: 'GCash',
          icon: Icons.account_balance_wallet_outlined,
          onTap: () => onSelect('gcash'),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTypography.subheading)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ],
      ),
    );
  }
}

class _FailedPaymentBody extends StatelessWidget {
  const _FailedPaymentBody({
    required this.channel,
    required this.expired,
    required this.onReturnToCart,
    required this.onTryAgain,
  });

  final String? channel;
  final bool expired;
  final VoidCallback onReturnToCart;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final method = channel == 'gcash'
        ? 'GCash payment'
        : channel == 'card'
        ? 'card payment'
        : 'payment';
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          expired ? 'Payment Expired' : 'Payment Failed',
          style: AppTypography.display,
        ),
        const SizedBox(height: 8),
        Text(
          expired
              ? 'Payment expired. Your order was not completed.\nNo purchase was finalized.\n\nThe item is still in your cart.'
              : 'Your $method was not completed.\nNo purchase was finalized.\n\nThe item is still in your cart.',
          style: AppTypography.body,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        ThriftButton(label: 'Return to Cart', onPressed: onReturnToCart),
        const SizedBox(height: 12),
        ThriftButton(
          label: 'Try Again',
          variant: ThriftButtonVariant.outline,
          onPressed: onTryAgain,
        ),
      ],
    );
  }
}

class _PaidPaymentBody extends StatelessWidget {
  const _PaidPaymentBody({
    required this.orderNumber,
    required this.channel,
    required this.onViewOrder,
  });

  final String orderNumber;
  final String? channel;
  final VoidCallback onViewOrder;

  @override
  Widget build(BuildContext context) {
    final method = channel == 'gcash'
        ? 'GCash payment received.'
        : channel == 'card'
        ? 'Card payment received.'
        : 'Your payment has been successfully confirmed.';
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            size: 64,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 24),
        Text('Payment Successful', style: AppTypography.display),
        const SizedBox(height: 8),
        Text(method, style: AppTypography.body, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Order #$orderNumber has been paid successfully.\nThe seller can now prepare your order.',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        ThriftButton(label: 'View Order', onPressed: onViewOrder),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}
