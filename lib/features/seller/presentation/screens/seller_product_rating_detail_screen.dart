import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../controllers/seller_product_ratings_controller.dart';
import '../widgets/seller_review_widgets.dart';

class SellerProductRatingDetailScreen extends StatelessWidget {
  const SellerProductRatingDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerProductRatingsController>();
    final summary = controller.summaryForProduct(productId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          summary?.productTitle ?? 'Product reviews',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: controller.isLoading && summary == null
            ? const Center(child: CircularProgressIndicator())
            : summary == null
            ? SellerRatingsEmptyState(
                title: 'Product not found',
                message:
                    'We could not find reviews for this product in your shop.',
                icon: Icons.search_off_outlined,
              )
            : ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                children: [
                  SellerRatingSummaryHeader(
                    averageRating: summary.averageRating,
                    reviewCount: summary.reviewCount,
                    title: summary.productTitle,
                    subtitle: 'Buyer reviews for this product',
                    icon: Icons.shopping_bag_outlined,
                  ),
                  const SizedBox(height: 16),
                  ...summary.reviews.map(
                    (review) => SellerReviewListTile(review: review),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}
