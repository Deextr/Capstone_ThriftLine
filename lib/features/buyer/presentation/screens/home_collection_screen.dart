import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/product_card.dart';
import '../../controllers/home_collection_controller.dart';
import '../../controllers/home_controller.dart';
import '../widgets/verified_seller_card.dart';

class HomeCollectionScreen extends StatelessWidget {
  const HomeCollectionScreen({super.key, required this.type});

  final HomeCollectionType type;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeCollectionController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(controller.title),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: controller.load,
          child: _body(context, controller),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, HomeCollectionController controller) {
    if (controller.isLoading &&
        controller.products.isEmpty &&
        controller.sellers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ],
      );
    }

    if (controller.hasError &&
        controller.products.isEmpty &&
        controller.sellers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(
            controller.isOffline
                ? Icons.wifi_off_rounded
                : Icons.error_outline_rounded,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            controller.errorMessage ?? 'Something went wrong',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton(
              onPressed: controller.load,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (type == HomeCollectionType.verifiedSellers) {
      if (controller.sellers.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 48),
            Text(
              'No verified shops to show yet.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      }
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: controller.sellers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            VerifiedSellerCard(seller: controller.sellers[i]),
      );
    }

    if (controller.products.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Text(
            'Nothing to show here yet. Pull to refresh.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          gridDelegate: ProductCard.gridDelegateFor(
            maxWidth: constraints.maxWidth,
            horizontalPadding: 32,
            compact: true,
            textScale: textScale,
          ),
          itemCount: controller.products.length,
          itemBuilder: (_, i) {
            final p = controller.products[i];
            return ProductCard(
              product: p,
              compact: true,
              showCountdown:
                  type == HomeCollectionType.endingSoon ||
                  type == HomeCollectionType.bidding,
              cartAddCount: controller.cartCounts[p.id],
              onTap: () => context.push('/product/${p.id}'),
            );
          },
        );
      },
    );
  }
}
