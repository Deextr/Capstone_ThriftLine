import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_orders_controller.dart';
import '../../data/paymongo_checkout.dart';

class PayNowButton extends StatelessWidget {
  const PayNowButton({
    super.key,
    required this.orderId,
    required this.channel,
    required this.amountLabel,
    this.expand = true,
  });

  final String orderId;
  final String channel;
  final String amountLabel;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerOrdersController>();
    return ThriftButton(
      label: controller.isStartingPayment
          ? 'Opening PayMongo…'
          : 'Pay $amountLabel',
      isLoading: controller.isStartingPayment,
      expand: expand,
      onPressed: controller.isStartingPayment
          ? null
          : () => startPaymongoPayment(
              context: context,
              controller: controller,
              orderId: orderId,
              channel: channel,
            ),
    );
  }
}

Future<void> startPaymongoPayment({
  required BuildContext context,
  required BuyerOrdersController controller,
  required String orderId,
  required String channel,
}) async {
  final result = await controller.startPaymongoCheckout(
    orderId,
    channel: channel,
  );
  if (!context.mounted) return;

  if (result.alreadyPaid) {
    showThriftSnackBar(context, 'This order is already paid.');
    return;
  }

  final checkoutUrl = result.checkoutUrl;
  if (result.success &&
      checkoutUrl != null &&
      isSafePaymongoCheckoutUrl(checkoutUrl)) {
    final launched = await launchUrl(
      Uri.parse(checkoutUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      showThriftSnackBar(
        context,
        'Unable to open PayMongo. Please try again.',
        isError: true,
      );
    }
    return;
  }

  showThriftSnackBar(
    context,
    result.error ?? 'Unable to start payment right now. Please try again.',
    isError: true,
  );
}
