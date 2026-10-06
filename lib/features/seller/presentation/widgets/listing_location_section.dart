import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/public_item_location.dart';
import '../../../../widgets/thrift_widgets.dart';

class ListingLocationSection extends StatelessWidget {
  const ListingLocationSection({
    super.key,
    required this.showItemLocation,
    required this.sellerBarangay,
    required this.onToggle,
    this.showHeading = true,
  });

  final bool showItemLocation;
  final String? sellerBarangay;
  final ValueChanged<bool> onToggle;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final preview = formatPublicItemLocation(
      showItemLocation: true,
      sellerBarangay: sellerBarangay,
    );
    final hasBarangay = preview != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text('Item location', style: AppTypography.subheading),
          const SizedBox(height: 4),
          Text(
            'Uses your shop barangay from Become a Seller. Buyers never see your street address.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text('Show item location', style: AppTypography.label),
          subtitle: hasBarangay
              ? Text(
                  showItemLocation
                      ? 'Buyers will see: $preview'
                      : 'Location hidden on this listing',
                  style: AppTypography.caption,
                )
              : Text(
                  'Add your shop barangay in Shop address first.',
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
          value: showItemLocation && hasBarangay,
          onChanged: hasBarangay ? onToggle : null,
          activeThumbColor: AppColors.primary,
        ),
        if (!hasBarangay) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(RouteNames.sellerShopAddress),
              child: const Text('Update shop address'),
            ),
          ),
        ],
      ],
    );
  }
}
