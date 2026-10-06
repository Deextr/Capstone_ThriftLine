import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/listing_shipping.dart';
import '../../controllers/add_listing_controller.dart' show ListingFormat;
import '../../../../widgets/thrift_widgets.dart';

class ListingShippingSection extends StatelessWidget {
  const ListingShippingSection({
    super.key,
    required this.listingFormat,
    required this.shippingMode,
    required this.onModeChanged,
    required this.shippingFeeController,
    required this.qtyThresholdController,
    required this.bidThresholdController,
    required this.startingBidText,
    this.shippingFeeError,
    this.qtyThresholdError,
    this.bidThresholdError,
    this.readOnly = false,
    this.showHeading = true,
  });

  final ListingFormat listingFormat;
  final ListingShippingMode shippingMode;
  final ValueChanged<ListingShippingMode> onModeChanged;
  final TextEditingController shippingFeeController;
  final TextEditingController qtyThresholdController;
  final TextEditingController bidThresholdController;
  final String startingBidText;
  final String? shippingFeeError;
  final String? qtyThresholdError;
  final String? bidThresholdError;
  final bool readOnly;
  final bool showHeading;

  bool get _isAuction => listingFormat == ListingFormat.auction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text('Shipping', style: AppTypography.subheading),
          if (readOnly) ...[
            const SizedBox(height: 4),
            Text(
              'Shipping cannot be changed after bidding has started.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ] else if (readOnly) ...[
          Text(
            'Shipping cannot be changed after bidding has started.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        _ShippingChoice(
          label: 'Free shipping',
          hint: _isAuction
              ? 'Winner pays no shipping fee'
              : 'Buyer pays ₱0 shipping for this shop order',
          selected: shippingMode == ListingShippingMode.free,
          onTap: readOnly ? null : () => onModeChanged(ListingShippingMode.free),
        ),
        _ShippingChoice(
          label: 'Fixed shipping fee',
          hint: 'One fee per seller order at checkout',
          selected: shippingMode == ListingShippingMode.fixedFee,
          onTap: readOnly ? null : () => onModeChanged(ListingShippingMode.fixedFee),
        ),
        if (!_isAuction)
          _ShippingChoice(
            label: 'Free shipping at quantity',
            hint: 'Counts all items from your shop in the buyer\'s cart',
            selected: shippingMode == ListingShippingMode.quantityThreshold,
            onTap: readOnly
                ? null
                : () => onModeChanged(ListingShippingMode.quantityThreshold),
          )
        else
          _ShippingChoice(
            label: 'Free shipping at bid amount',
            hint: 'Uses the winning (or second-chance) bid amount',
            selected: shippingMode == ListingShippingMode.bidThreshold,
            onTap: readOnly
                ? null
                : () => onModeChanged(ListingShippingMode.bidThreshold),
          ),
        if (shippingMode == ListingShippingMode.fixedFee ||
            shippingMode == ListingShippingMode.quantityThreshold ||
            shippingMode == ListingShippingMode.bidThreshold) ...[
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Shipping fee (₱)',
            hint: '80',
            controller: shippingFeeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: shippingFeeError,
            readOnly: readOnly,
          ),
        ],
        if (shippingMode == ListingShippingMode.quantityThreshold) ...[
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Free shipping quantity',
            hint: '3',
            controller: qtyThresholdController,
            keyboardType: TextInputType.number,
            error: qtyThresholdError,
            readOnly: readOnly,
          ),
        ],
        if (shippingMode == ListingShippingMode.bidThreshold) ...[
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Free shipping at bid (₱)',
            hint: '500',
            controller: bidThresholdController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: bidThresholdError,
            readOnly: readOnly,
          ),
          if (startingBidText.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Starting bid: $startingBidText',
                style: AppTypography.caption,
              ),
            ),
        ],
      ],
    );
  }
}

class _ShippingChoice extends StatelessWidget {
  const _ShippingChoice({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.25)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.label),
                    Text(hint, style: AppTypography.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
