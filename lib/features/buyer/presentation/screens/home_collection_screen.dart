import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/product_card.dart';
import '../../controllers/home_collection_controller.dart';
import '../../controllers/home_controller.dart';
import '../widgets/home_section_widgets.dart';
import '../widgets/verified_seller_card.dart';

class HomeCollectionScreen extends StatefulWidget {
  const HomeCollectionScreen({super.key, required this.type});

  final HomeCollectionType type;

  @override
  State<HomeCollectionScreen> createState() => _HomeCollectionScreenState();
}

class _HomeCollectionScreenState extends State<HomeCollectionScreen> {
  static const double _loadMoreTriggerPx = 280;

  void _onScroll(ScrollNotification notification, HomeCollectionController c) {
    if (!c.supportsInfiniteScroll || !c.hasMore || c.isLoadingMore) {
      return;
    }
    if (notification.metrics.pixels <
        notification.metrics.maxScrollExtent - _loadMoreTriggerPx) {
      return;
    }
    c.loadMore();
  }

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
        children: const [SizedBox(height: 8), HomeGridShimmer()],
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

    if (widget.type == HomeCollectionType.verifiedSellers) {
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

    final footerCount =
        (controller.isLoadingMore ? 1 : 0) +
        (controller.loadMoreError != null && !controller.isLoadingMore ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
              _onScroll(n, controller);
            }
            return false;
          },
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            gridDelegate: ProductCard.gridDelegateFor(
              maxWidth: constraints.maxWidth,
              horizontalPadding: 32,
              compact: true,
              textScale: textScale,
            ),
            itemCount: controller.products.length + footerCount,
            itemBuilder: (_, i) {
              if (i < controller.products.length) {
                final p = controller.products[i];
                return ProductCard(
                  product: p,
                  compact: true,
                  showCountdown:
                      widget.type == HomeCollectionType.endingSoon ||
                      widget.type == HomeCollectionType.bidding,
                  cartAddCount: controller.cartCounts[p.id],
                  onTap: () => context.push('/product/${p.id}'),
                );
              }
              if (controller.isLoadingMore && i == controller.products.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: TextButton(
                  onPressed: controller.loadMore,
                  child: Text(
                    controller.loadMoreError ?? 'Load more',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
