import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Prompts the buyer to verify phone before bidding; preserves product context.
Future<void> showBidPhoneVerificationPrompt(
  BuildContext context, {
  required String productId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Verify your phone number'),
      content: Text(
        'Verify your phone number to place a bid.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            context.push(RouteNames.verifyPhoneForBidReturn(productId));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Verify phone number'),
        ),
      ],
    ),
  );
}
