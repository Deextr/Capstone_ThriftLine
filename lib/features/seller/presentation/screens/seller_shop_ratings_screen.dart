import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../controllers/seller_shop_ratings_controller.dart';
import '../widgets/seller_review_widgets.dart';

class SellerShopRatingsScreen extends StatelessWidget {
  const SellerShopRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerShopRatingsController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Shop Ratings')),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: controller.load,
          child: _body(context, controller),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SellerShopRatingsController controller) {
    if (controller.isLoading && controller.shopReviews.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.hasError && controller.shopReviews.isEmpty) {
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
    if (controller.shopReviews.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SellerRatingsEmptyState(
            title: 'No shop reviews yet',
            message:
                'When buyers rate your shop after completed orders, their feedback will show here.',
            icon: Icons.storefront_outlined,
          ),
        ],
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      children: [
        SellerRatingSummaryHeader(
          averageRating: controller.averageRating,
          reviewCount: controller.reviewCount,
          title: 'Your shop rating',
          subtitle: 'Overall score from buyer reviews on your shop',
          icon: Icons.storefront_outlined,
        ),
        const SizedBox(height: 16),
        Text('Customer reviews', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...controller.shopReviews.map(
          (review) => SellerReviewListTile(review: review),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
