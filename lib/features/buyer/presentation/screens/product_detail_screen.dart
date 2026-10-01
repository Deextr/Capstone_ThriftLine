import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/seller_trust.dart';
import '../../../../core/utils/stock_limits.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/saved_items_provider.dart';
import '../../../../widgets/countdown_timer.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/presentation/widgets/end_auction_dialog.dart';
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

  Future<void> _endAuctionEarly(
    BuildContext context,
    ProductDetailController controller,
  ) async {
    final accepted = await confirmEndAuctionEarly(
      context,
      highestBid: controller.currentBidAmount,
    );
    if (!accepted || !context.mounted) return;
    final error = await controller.endAuctionEarly();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      'Auction ended. The winner has 12 hours to pay.',
    );
  }

  Future<void> _sellerOfferNextBidder(
    BuildContext context,
    ProductDetailController controller,
  ) async {
    final winnerId = controller.auction?['winner_id'] as String?;
    final winningBid = controller.bids.isNotEmpty
        ? controller.bids.first
        : null;
    final candidateBids = controller.bids.where((b) {
      final bidderId = b['bidder_id'] as String?;
      return bidderId != winnerId;
    }).toList();

    if (candidateBids.isEmpty) {
      showThriftSnackBar(
        context,
        'No other valid bidders found for this auction round. You can relist the item.',
        isError: true,
      );
      return;
    }

    final nextBid = candidateBids.first;
    final bidder = nextBid['bidder'] as Map<String, dynamic>?;
    final username =
        bidder?['username'] as String? ??
        bidder?['full_name'] as String? ??
        'Next highest bidder';
    final amount = (nextBid['bid_amount'] as num?)?.toDouble() ?? 0.0;
    final nextTime = nextBid['created_at'] != null
        ? DateTime.tryParse(nextBid['created_at'] as String)
        : null;

    final winBidder = winningBid?['bidder'] as Map<String, dynamic>?;
    final winUsername = winBidder?['username'] as String? ?? 'Previous Winner';
    final winAmount = (winningBid?['bid_amount'] as num?)?.toDouble() ?? 0.0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Offer to 2nd Highest Bidder',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The previous winning buyer failed or cancelled. You can pass the item to the next-highest bidder:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),

              // 2nd Highest Bidder Card (Highlighted)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '2nd Highest Bidder',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (nextTime != null)
                          Text(
                            formatRelativeTime(nextTime),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$username',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (bidder?['full_name'] != null &&
                                  bidder?['full_name'] != username)
                                Text(
                                  bidder!['full_name'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency(amount),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Comparison with 1st bidder (Previous/Failed)
              if (winningBid != null && winAmount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1st Bid (@$winUsername - Expired):',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        formatCurrency(winAmount),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'They will have a 12-hour window to complete checkout at their bid price.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Send Offer (${formatCurrency(amount)})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await controller.offerToNextBidder();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Offer sent to @$username.');
  }

  Future<void> _sellerRelist(
    BuildContext context,
    ProductDetailController controller,
  ) async {
    final startPriceCtrl = TextEditingController(
      text: controller.auctionStartingPrice.toStringAsFixed(0),
    );
    final minIncrementCtrl = TextEditingController(
      text: controller.auctionMinimumIncrement.toStringAsFixed(0),
    );
    int selectedDays = controller.auctionDurationDays;
    if (![1, 3, 5, 7].contains(selectedDays)) selectedDays = 3;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Relist Auction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update auction details before restarting:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: startPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Starting Price (₱)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minIncrementCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Minimum Bid Increment (₱)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Auction Duration:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 3, 5, 7].map((d) {
                      final isSelected = selectedDays == d;
                      return ChoiceChip(
                        label: Text('$d day${d == 1 ? '' : 's'}'),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedDays = d);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text(
                  'Relist Item',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final parsedStart = double.tryParse(startPriceCtrl.text.trim());
    final parsedIncr = double.tryParse(minIncrementCtrl.text.trim());

    final error = await controller.relistAuction(
      selectedDays,
      startingPrice: parsedStart != null && parsedStart > 0
          ? parsedStart
          : null,
      minimumIncrement: parsedIncr != null && parsedIncr > 0
          ? parsedIncr
          : null,
    );
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Auction relisted.');
  }

  Future<void> _proceedToWinnerCheckout(
    BuildContext context,
    ProductDetailController controller,
  ) async {
    final orderId = await controller.getWonAuctionOrderId();
    if (!context.mounted) return;
    if (orderId == null || orderId.isEmpty) {
      showThriftSnackBar(
        context,
        'Your pending order is not ready yet. Please try again.',
        isError: true,
      );
      return;
    }
    context.push(RouteNames.paymentForOrder(orderId));
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
                        format: formatReadableCountdown,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
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
                      if (product.sellerTrustScore != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${resolveTrustLabel(score: product.sellerTrustScore!, storedLevel: product.sellerTrustLevel)} · ${product.sellerTrustScore}/100',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
    final title = controller.bidRound > 1
        ? 'Recent Bids (Round ${controller.bidRound})'
        : 'Recent Bids';
    return _buildSectionCard(
      title,
      Column(
        children: controller.bids.take(5).map<Widget>((b) {
          final bidder = b['bidder'] as Map<String, dynamic>?;
          final username = bidder?['username'] as String? ?? 'Anonymous';
          final isViewer = controller.isViewerBid(b);
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
                    Row(
                      children: [
                        Text(
                          username,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isViewer) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
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
    final isAuction = controller.isAuction;

    if (listingUsesShoppingCart(product.sellingType) && !isAuction) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _addFixedPriceToCart(context, cart, product),
              icon: const Icon(
                Icons.add_shopping_cart_outlined,
                color: AppColors.textPrimary,
                size: 20,
              ),
              label: Text(
                'Add to Cart',
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
              onPressed: () => _buyNow(context, cart, product),
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

    // Auction layout
    if (isAuction) {
      if (controller.isOwnListing) {
        if (controller.isAuctionActive) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: controller.canEndAuctionEarly
                  ? () => _endAuctionEarly(context, controller)
                  : null,
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
              child: Text(
                controller.canEndAuctionEarly
                    ? 'End auction early'
                    : 'Waiting for bids',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        // Seller viewing ended auction: can relist or offer to next bidder
        return Row(
          children: [
            if (controller.canOfferToNextBidder) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _sellerOfferNextBidder(context, controller),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Offer Next Bidder',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: () => _sellerRelist(context, controller),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Relist Auction',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      // Buyer view of active auction
      if (controller.isAuctionActive) {
        if (controller.isViewerLeading) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                "You're the Highest Bidder",
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: AppColors.success,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showBidBottomSheet(context, controller, minBid),
            icon: const Icon(
              Icons.gavel_rounded,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              'Place Bid',
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
        );
      }

      // Ended auction for buyer: winner checkout vs ended status
      if (controller.isViewerWinner) {
        final due = controller.paymentDueAt;
        String payLabel = 'Proceed to Checkout';
        if (due != null) {
          final diff = due.difference(DateTime.now());
          if (!diff.isNegative) {
            final hours = diff.inHours;
            final mins = diff.inMinutes % 60;
            payLabel = 'Proceed to Checkout (${hours}h ${mins}m left)';
          }
        }
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _proceedToWinnerCheckout(context, controller),
            icon: const Icon(
              Icons.payment_rounded,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              payLabel,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      }

      final label = controller.isViewerExpiredWinner
          ? 'Payment Expired — Item No Longer Available'
          : controller.hasNoWinner
          ? 'Auction Ended — No Winner'
          : 'Auction Ended';

      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.textHint,
            disabledBackgroundColor: AppColors.textHint,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _addFixedPriceToCart(
    BuildContext context,
    CartProvider cart,
    ProductModel product,
  ) async {
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
    final error = cart.errorMessage;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Added to cart');
  }

  Future<void> _buyNow(
    BuildContext context,
    CartProvider cart,
    ProductModel product,
  ) async {
    if (product.maxPurchasableQuantity <= 0) {
      showThriftSnackBar(
        context,
        '${product.title} is no longer available.',
        isError: true,
      );
      return;
    }
    if (!cart.isInCart(product.id)) {
      await cart.addToCart(product);
      if (!context.mounted) return;
      final error = cart.errorMessage;
      if (error != null || !cart.isInCart(product.id)) {
        showThriftSnackBar(
          context,
          error ?? 'Could not start checkout for this item.',
          isError: true,
        );
        return;
      }
    }
    context.push(RouteNames.checkoutFor(productId: product.id));
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
