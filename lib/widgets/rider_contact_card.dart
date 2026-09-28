import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../models/order_model.dart';
import '../models/shipment_model.dart';

/// Compact buyer-facing contact card. The phone is intentionally formatted
/// for readability, never masked: this card is only rendered for the buyer's
/// own active local-rider shipment.
class BuyerRiderContactCard extends StatelessWidget {
  const BuyerRiderContactCard({
    super.key,
    required this.shipment,
    this.onCall,
    this.onMessage,
  });

  final ShipmentModel shipment;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    if (!shipment.shouldShowBuyerRiderInfo) return const SizedBox.shrink();
    final hasPhone = shipment.hasRiderPhone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Rider', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shipment.buyerRiderDisplayName(),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPhone
                        ? shipment.buyerRiderPhone()
                        : 'Contact number unavailable',
                    style: AppTypography.body,
                    semanticsLabel: hasPhone
                        ? 'Rider contact ${shipment.buyerRiderPhone()}'
                        : 'Contact number unavailable',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (onCall != null || onMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (onCall != null)
                Expanded(
                  child: Semantics(
                    button: true,
                    enabled: hasPhone,
                    label: 'Call Rider',
                    child: OutlinedButton.icon(
                      onPressed: hasPhone ? onCall : null,
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Call Rider'),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              if (onCall != null && onMessage != null) const SizedBox(width: 8),
              if (onMessage != null)
                Expanded(
                  child: Semantics(
                    button: true,
                    enabled: hasPhone,
                    label: 'Message Rider',
                    child: ElevatedButton.icon(
                      onPressed: hasPhone ? onMessage : null,
                      icon: const Icon(Icons.message_outlined, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Message Rider'),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class BuyerCourierInfo extends StatelessWidget {
  const BuyerCourierInfo({super.key, required this.order, this.onTrack});

  final OrderModel order;
  final VoidCallback? onTrack;

  @override
  Widget build(BuildContext context) {
    final courier = order.courier?.trim();
    final tracking = order.trackingNumber?.trim();
    if ((courier == null || courier.isEmpty) &&
        (tracking == null || tracking.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Courier', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text(
          courier?.isNotEmpty == true ? courier! : 'Official courier',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        if (tracking?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text('Tracking Number  $tracking', style: AppTypography.body),
        ],
        if (onTrack != null && tracking?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTrack,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Track Package'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ],
    );
  }
}
