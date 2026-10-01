import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

/// Confirms an early close. Returns true only when the seller accepts.
Future<bool> confirmEndAuctionEarly(
  BuildContext context, {
  required double highestBid,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('End auction early?'),
      content: Text(
        'The highest bid is ${formatCurrency(highestBid)}. '
        'Bidding will stop and that bidder has 12 hours to pay. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep bidding'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('End auction'),
        ),
      ],
    ),
  );
  return accepted == true;
}
