import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/saved_items_provider.dart';
import '../../../../widgets/countdown_timer.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/product_detail_controller.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with WidgetsBindingObserver {
  final _bidController = TextEditingController();
  late final PageController _pageController;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ProductDetailController>().reconcileOnResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _bidController.dispose();
    super.dispose();
  }

  Future<void> _openSellerChat() async {
    final result = await context
        .read<ProductDetailController>()
        .openSellerConversation();
    if (!mounted) return;
    if (result.error != null) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    final id = result.conversationId;
    if (id == null) return;
    context.push(RouteNames.chatThread(id));
  }

  void _showBidBottomSheet(
    BuildContext context,
    ProductDetailController controller,
    double minBid,
  ) {
    _bidController.text = minBid.toStringAsFixed(0);
    ThriftBottomSheet.show(
      context,
      title: 'Place a Bid',
      child: StatefulBuilder(
        builder: (context, setStateSB) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Bid: ${formatCurrency(controller.currentBidAmount)}',
                style: AppTypography.subheading,
              ),
              const SizedBox(height: 4),
              Text(
                'Minimum next bid: ${formatCurrency(minBid)}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final v =
                          (double.tryParse(_bidController.text) ?? minBid) -
                          controller.minimumIncrement;
                      if (v >= minBid) {
                        setStateSB(
                          () => _bidController.text = v.toStringAsFixed(0),
                        );
                      }
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Expanded(
                    child: ThriftTextField(
                      controller: _bidController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final v =
                          (double.tryParse(_bidController.text) ?? minBid) +
                          controller.minimumIncrement;
                      setStateSB(
                        () => _bidController.text = v.toStringAsFixed(0),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ThriftButton(
                label: 'Confirm Bid',
                variant: ThriftButtonVariant.primary,
                onPressed: () async {
                  final cleanText = _bidController.text.replaceAll(
                    RegExp(r'[^\d.]'),
                    '',
                  );
                  final amount = double.tryParse(cleanText) ?? minBid;
                  final error = await controller.placeBid(amount);
                  if (context.mounted) {
                    Navigator.pop(context);
                    if (error == null) {
                      showThriftSnackBar(context, 'Bid placed successfully!');
                    } else {
                      showThriftSnackBar(context, error, isError: true);
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProductDetailController>();

    // â”€â”€ Loading state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (controller.isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBarRow(context),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // â”€â”€ Error state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (controller.hasError || controller.product == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBarRow(context),
              Expanded(
                child: _ErrorBody(
                  message: controller.errorMessage ?? 'Product not found',
                  onRetry: controller.refresh,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final product = controller.product!;
    final minBid = controller.minimumNextBid;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildBottomBar(
        context,
        product,
        controller,
        minBid,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: controller.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopStack(context, product, controller),

              const SizedBox(height: 16),

              // Price & Bidding Card â€” positioned cleanly below picture
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildPriceCardContent(product, controller),
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.brand ?? 'Unbranded',
                      style: AppTypography.subheading.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.title,
                      style: AppTypography.heading.copyWith(
                        fontSize: 22,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Attributes Row
                    Row(
                      children: [
                        _buildAttributeBox('Size', product.size ?? 'N/A'),
                        const SizedBox(width: 8),
                        _buildAttributeBox(
                          'Condition',
                          product.condition.label,
                        ),
                        const SizedBox(width: 8),
                        _buildAttributeBox('Color', product.color ?? 'N/A'),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Seller Card
                    _buildSellerCard(product),

                    const SizedBox(height: 16),

                    // Description
                    _buildSectionCard(
                      'Description',
                      Text(
                        product.description,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Product details (listing info)
                    _buildDetailsCard(product),

                    const SizedBox(height: 16),

                    // Recent Bids (auction only)
                    if (controller.isAuction && controller.bids.isNotEmpty)
                      _buildRecentBidsCard(controller),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Minimal back-button row used for loading/error states.
  Widget _buildAppBarRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStack(
    BuildContext context,
    ProductModel product,
    ProductDetailController controller,
  ) {
    final images = product.imageUrls.isNotEmpty
        ? product.imageUrls
        : [product.imageUrl];

    return Column(
      children: [
        Stack(
          children: [
            // Image Carousel
            SizedBox(
              height: 380,
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _imageIndex = i),
                children: images
                    .map<Widget>(
                      (url) => CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, _) =>
                            Container(color: AppColors.surfaceVariant),
                        errorWidget: (_, _, _) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textHint,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            // Gradient overlay at top for icons visibility
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Top Left Back Button
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              child: _CircularButton(
                icon: Icons.arrow_back,
                onTap: () => context.pop(),
              ),
            ),

            // Top Right Actions
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 16,
              child: Row(
                children: [
                  Consumer<SavedItemsProvider>(
                    builder: (context, savedItems, _) {
                      final isSaved = savedItems.isSaved(product.id);
                      return _CircularButton(
                        icon: isSaved ? Icons.favorite : Icons.favorite_border,
                        iconColor: isSaved
                            ? AppColors.error
                            : AppColors.textPrimary,
                        onTap: () => savedItems.toggleSave(product.id, product),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _CircularButton(
                    icon: Icons.share_outlined,
                    onTap: () => showThriftSnackBar(context, 'Link copied!'),
                  ),
                ],
              ),
            ),

            // Timer pill (auction) — stays visible after expiry as "Ended"
            if (controller.isAuction && controller.auctionEndTime != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: controller.isAuctionActive
                        ? AppColors.primary
                        : AppColors.textHint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      CountdownTimer(
                        endTime: controller.auctionEndTime!,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        onExpired: () {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            context
                                .read<ProductDetailController>()
                                .reconcileOnResume();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // Previous / Next image arrows
            if (images.length > 1) ...[
              if (_imageIndex > 0)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CircularButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                    ),
                  ),
                ),
              if (_imageIndex < images.length - 1)
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CircularButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),

        // Indicator dots below the image
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              images.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _imageIndex == i ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _imageIndex == i
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceCardContent(
    ProductModel product,
    ProductDetailController controller,
  ) {
    final isAuction = controller.isAuction;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAuction) ...[
              Row(
                children: [
                  const Icon(
                    Icons.gavel_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Current Bid',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatCurrency(controller.currentBidAmount),
                style: AppTypography.heading.copyWith(
                  color: AppColors.primary,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${controller.bidCount} bid${controller.bidCount == 1 ? '' : 's'} placed',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (controller.viewerAuctionStatus != null) ...[
                const SizedBox(height: 4),
                Text(
                  controller.viewerAuctionStatus!,
                  style: AppTypography.caption.copyWith(
                    color: controller.isViewerLeading
                        ? AppColors.success
                        : AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ] else ...[
              Text(
                'Price',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatCurrency(product.price),
                style: AppTypography.heading.copyWith(
                  color: AppColors.primary,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Fixed Price',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isAuction) ...[
              Text(
                'Starting Price',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                formatCurrency(product.price),
                style: AppTypography.subheading.copyWith(
                  color: AppColors.textHint,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ] else ...[
              // Listing type badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildAttributeBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerCard(ProductModel product) {
    return GestureDetector(
      onTap: () => context.push('/seller-profile/${product.sellerUsername}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seller',
              style: AppTypography.subheading.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ThriftAvatar(imageUrl: product.sellerAvatar, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.sellerName,
                              style: AppTypography.subheading.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (product.sellerVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (product.sellerUsername.isNotEmpty)
                        Text(
                          '@${product.sellerUsername}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 4),
                      if (product.location != null &&
                          product.location!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.textSecondary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              product.location!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.primary,
                  size: 22,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(ProductModel product) {
    final details = <MapEntry<String, String>>[];
    if (product.category.label.isNotEmpty) {
      details.add(MapEntry('Category', product.category.label));
    }
    if (product.brand != null && product.brand!.isNotEmpty) {
      details.add(MapEntry('Brand', product.brand!));
    }
    if (product.size != null && product.size!.isNotEmpty) {
      details.add(MapEntry('Size', product.size!));
    }
    if (product.color != null && product.color!.isNotEmpty) {
      details.add(MapEntry('Color', product.color!));
    }
    details.add(MapEntry('Condition', product.condition.label));
    details.add(MapEntry('Listed', formatRelativeTime(product.createdAt)));
    details.add(MapEntry('Views', product.viewCount.toString()));
    details.add(MapEntry('Favorites', product.favoriteCount.toString()));

    if (details.isEmpty) return const SizedBox.shrink();

    return _buildSectionCard(
      'Item Details',
      Column(
        children: details
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      e.value,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildSectionCard(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildRecentBidsCard(ProductDetailController controller) {
    return _buildSectionCard(
      'Recent Bids',
      Column(
        children: controller.bids.take(5).map<Widget>((b) {
          final bidder = b['bidder'] as Map<String, dynamic>?;
          final username = bidder?['username'] as String? ?? 'Anonymous';
          final amount = (b['bid_amount'] as num?)?.toDouble() ?? 0;
          final createdAt = b['created_at'] != null
              ? DateTime.parse(b['created_at'] as String)
              : DateTime.now();

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      formatRelativeTime(createdAt),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                Text(
                  formatCurrency(amount),
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ProductModel product,
    ProductDetailController controller,
    double minBid,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: _buildActionButtons(context, product, controller, minBid),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ProductModel product,
    ProductDetailController controller,
    double minBid,
  ) {
    final cart = context.watch<CartProvider>();
    final isFixed = product.sellingType == SellingType.fixedPrice;
    final isAuction = controller.isAuction;
    final inCart = cart.isInCart(product.id);

    // Fixed price layout
    if (isFixed) {
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton.icon(
              onPressed: _openSellerChat,
              icon: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.textPrimary,
                size: 20,
              ),
              label: Text(
                'Chat',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: const BorderSide(color: AppColors.border, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (product.maxPurchasableQuantity <= 0) {
                  showThriftSnackBar(
                    context,
                    '${product.title} is no longer available.',
                    isError: true,
                  );
                  return;
                }
                if (!inCart) {
                  await cart.addToCart(product);
                  if (!context.mounted) return;
                  showThriftSnackBar(context, 'Added to cart!');
                  context.push('${RouteNames.checkout}?product=${product.id}');
                  return;
                }
                context.push(RouteNames.checkout);
              },
              icon: Icon(
                inCart
                    ? Icons.shopping_bag_rounded
                    : Icons.shopping_bag_outlined,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                inCart ? 'View Cart' : 'Buy Now',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Auction layout
    if (isAuction) {
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton.icon(
              onPressed: _openSellerChat,
              icon: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.textPrimary,
                size: 20,
              ),
              label: Text(
                'Chat',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: const BorderSide(color: AppColors.border, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: ElevatedButton.icon(
              onPressed: controller.isAuctionActive
                  ? () => _showBidBottomSheet(context, controller, minBid)
                  : null,
              icon: const Icon(
                Icons.gavel_rounded,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                controller.isAuctionActive ? 'Place Bid' : 'Auction Ended',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.textHint,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Fallback â€” generic layout (shouldn't normally be reached)
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openSellerChat,
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: AppColors.textPrimary,
              size: 20,
            ),
            label: Text(
              'Chat',
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              side: const BorderSide(color: AppColors.border, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              if (product.maxPurchasableQuantity <= 0) {
                showThriftSnackBar(
                  context,
                  '${product.title} is no longer available.',
                  isError: true,
                );
                return;
              }
              await cart.addToCart(product);
              if (!context.mounted) return;
              showThriftSnackBar(context, 'Added to cart!');
              context.push('${RouteNames.checkout}?product=${product.id}');
            },
            icon: const Icon(
              Icons.shopping_bag_outlined,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              'Buy Now',
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Helper widgets
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _CircularButton extends StatelessWidget {
  const _CircularButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 22),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            ),
          ),
        ],
      ),
    );
  }
}
