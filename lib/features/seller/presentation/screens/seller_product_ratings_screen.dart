import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/seller_product_ratings_controller.dart';
import '../widgets/seller_review_widgets.dart';

class SellerProductRatingsScreen extends StatelessWidget {
  const SellerProductRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerProductRatingsController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Product Ratings')),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: controller.load,
          child: _body(context, controller),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    SellerProductRatingsController controller,
  ) {
    if (controller.isLoading && controller.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.hasError && controller.products.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SellerRatingsErrorState(
            message: controller.errorMessage!,
            onRetry: controller.load,
          ),
        ],
      );
    }
    if (controller.products.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SellerRatingsEmptyState(
            title: 'No product reviews yet',
            message:
                'When buyers review items they purchased from you, each product will appear here with its ratings.',
            icon: Icons.inventory_2_outlined,
          ),
        ],
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      children: [
        Text('Ratings by product', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text(
          'These are buyer reviews tied to specific items you sold — separate from your overall shop score.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < controller.products.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SellerProductRatingTile(
            title: controller.products[i].productTitle,
            imageUrl: controller.products[i].productImageUrl,
            averageRating: controller.products[i].averageRating,
            reviewCount: controller.products[i].reviewCount,
            onTap: () => context.push(
              RouteNames.sellerProductRatingDetailFor(
                controller.products[i].productId,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
