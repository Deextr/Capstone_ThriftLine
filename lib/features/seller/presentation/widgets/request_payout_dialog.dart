import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../data/seller_payout_method.dart';

class RequestPayoutResult {
  const RequestPayoutResult._(this.confirmed, this.openPaymentMethods);

  final bool confirmed;
  final bool openPaymentMethods;

  static const none = RequestPayoutResult._(false, false);
  static const confirm = RequestPayoutResult._(true, false);
  static const addGcash = RequestPayoutResult._(false, true);
}

Future<RequestPayoutResult> showRequestPayoutDialog(
  BuildContext context, {
  required int availableCentavos,
  required SellerPayoutMethod? method,
}) async {
  final result = await showDialog<RequestPayoutResult>(
    context: context,
    builder: (dialogContext) {
      if (method == null || !method.isComplete) {
        return AlertDialog(
          title: const Text('Request Payout'),
          content: const Text(
            'No GCash account found. Add your GCash payment method first.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, RequestPayoutResult.none),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, RequestPayoutResult.addGcash),
              child: const Text('Add GCash'),
            ),
          ],
        );
      }

      final amount = formatCentavos(availableCentavos);
      return AlertDialog(
        title: const Text('Request Payout'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PayoutRow(label: 'Payout Amount', value: amount),
              _PayoutRow(
                label: 'Send to GCash',
                value:
                    '${method.accountName}\n${formatPhMobile(method.mobileNumber)}',
              ),
              const SizedBox(height: 4),
              Text(
                'This sends a request to ThriftLine. An admin transfers the '
                'money to your GCash by hand and adds the GCash reference '
                'here. It is not sent automatically.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, RequestPayoutResult.none),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, RequestPayoutResult.confirm),
            child: const Text('Send payout request'),
          ),
        ],
      );
    },
  );
  return result ?? RequestPayoutResult.none;
}

Future<void> openPaymentMethods(BuildContext context) {
  return context.push(RouteNames.paymentMethods);
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}
