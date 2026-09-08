import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/bid_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/bid_card.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_bids_controller.dart';

class BuyerBidsTab extends StatefulWidget {
  const BuyerBidsTab({super.key});

  @override
  State<BuyerBidsTab> createState() => _BuyerBidsTabState();
}

class _BuyerBidsTabState extends State<BuyerBidsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final bidsCtrl = context.watch<BuyerBidsController>();
    final username = auth.username ?? 'You';

    final activeBidsCount = bidsCtrl.activeBidsCount;
    final wonBidsCount = bidsCtrl.wonBidsCount;
    final lostBidsCount = bidsCtrl.lostBidsCount;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Bids', style: AppTypography.heading),
                const SizedBox(height: 4),
                Text(
                  'Track your auction activity',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'Active ($activeBidsCount)'),
                  Tab(text: 'Won ($wonBidsCount)'),
                  Tab(text: 'Lost ($lostBidsCount)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _bidList(
                  bidsCtrl.activeBids,
                  bidsCtrl,
                  data,
                  username,
                  BidTab.active,
                ),
                _bidList(
                  bidsCtrl.wonBids,
                  bidsCtrl,
                  data,
                  username,
                  BidTab.won,
                ),
                _bidList(
                  bidsCtrl.lostBids,
                  bidsCtrl,
                  data,
                  username,
                  BidTab.lost,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (_, i) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: ThriftCard(
          child: Row(
            children: [
              ShimmerBox(width: 72, height: 72, radius: 8),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: double.infinity, height: 16),
                    SizedBox(height: 8),
                    ShimmerBox(width: 100, height: 14),
                    SizedBox(height: 12),
                    ShimmerBox(width: 140, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bidList(
    List<UserBid> bids,
    BuyerBidsController bidsCtrl,
    DataProvider data,
    String username,
    BidTab tab,
  ) {
    if (bidsCtrl.isLoading) {
      return _buildSkeletonList();
    }

    if (bidsCtrl.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                bidsCtrl.error!,
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ThriftButton(
                label: 'Retry',
                expand: false,
                onPressed: bidsCtrl.refresh,
              ),
            ],
          ),
        ),
      );
    }

    if (bids.isEmpty) {
      String title = 'No bids here';
      String message = 'Check back later for updates.';
      String? actionLabel;
      VoidCallback? onAction;

      if (tab == BidTab.active) {
        title = 'No active bids';
        message = 'Find items you love and place real-time bids!';
        actionLabel = 'Explore Auctions';
        onAction = () => context.go(RouteNames.buyerHome);
      } else if (tab == BidTab.won) {
        title = 'No won auctions yet';
        message =
            'When you win an auction, it will appear here for checkout and delivery!';
      } else {
        title = 'No lost auctions';
        message = 'You have not lost any auctions.';
      }

      return EmptyState(
        icon: Icons.gavel,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }

    return RefreshIndicator(
      onRefresh: bidsCtrl.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bids.length,
        itemBuilder: (_, i) {
          final bid = bids[i];
          final product = bid.product ?? data.productById(bid.productId);
          if (product == null) return const SizedBox();

          Widget cardContent;

          if (tab == BidTab.won) {
            cardContent = ThriftCard(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.2),
                  ),
                ),
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AppColors.surfaceVariant),
                            errorWidget: (_, _, _) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(
                                Icons.image_outlined,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.title,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    'Winning bid: ',
                                    style: AppTypography.caption,
                                  ),
                                  Text(
                                    formatCurrency(bid.amount),
                                    style: AppTypography.subheading,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You won this auction! ðŸŽ‰',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ThriftButton(
                      label: 'Proceed to Payment',
                      onPressed: () => context.push('/buy-now/${product.id}'),
                    ),
                  ],
                ),
              ),
            );
          } else if (tab == BidTab.lost) {
            cardContent = ThriftCard(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AppColors.surfaceVariant),
                            errorWidget: (_, _, _) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(
                                Icons.image_outlined,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.title,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    'Final price: ',
                                    style: AppTypography.caption,
                                  ),
                                  Text(
                                    formatCurrency(
                                      product.currentBid ?? product.price,
                                    ),
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    'Your bid: ',
                                    style: AppTypography.caption,
                                  ),
                                  Text(
                                    formatCurrency(bid.amount),
                                    style: AppTypography.caption.copyWith(
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ThriftButton(
                      label: 'Find Similar',
                      variant: ThriftButtonVariant.outline,
                      onPressed: () => context.push(RouteNames.search),
                    ),
                  ],
                ),
              ),
            );
          } else {
            cardContent = BidCard(
              bid: bid,
              product: product,
              onTap: () => _showBidHistory(context, product, bid, username),
              onRaiseBid: bid.status == BidStatus.outbid
                  ? () => _raiseBid(context, product, bid)
                  : null,
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: cardContent,
          );
        },
      ),
    );
  }

  void _showBidHistory(
    BuildContext context,
    ProductModel product,
    UserBid bid,
    String myUsername,
  ) {
    final auctionId = bid.auctionId;
    final controller = context.read<BuyerBidsController>();

    ThriftBottomSheet.show(
      context,
      title: 'Bid History',
      child: FutureBuilder<List<BidEntry>>(
        future: auctionId != null && auctionId.isNotEmpty
            ? controller.fetchAuctionBids(auctionId)
            : Future.value(product.bidHistory),
        builder: (context, snapshot) {
          final history = (snapshot.data != null && snapshot.data!.isNotEmpty)
              ? snapshot.data!
              : product.bidHistory;

          if (snapshot.connectionState == ConnectionState.waiting &&
              history.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (history.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No bids recorded yet.')),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bidder', style: AppTypography.caption),
                    Text('Amount', style: AppTypography.caption),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              ...history.map<Widget>((b) {
                final isMe =
                    b.username == myUsername || b.username.contains('You');
                return Container(
                  color: isMe
                      ? AppColors.primaryLight.withValues(alpha: 0.3)
                      : Colors.transparent,
                  child: ListTile(
                    title: Row(
                      children: [
                        Text(
                          b.username,
                          style: AppTypography.body.copyWith(
                            fontWeight: isMe
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: AppTypography.caption.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      formatRelativeTime(b.createdAt),
                      style: AppTypography.caption.copyWith(fontSize: 10),
                    ),
                    trailing: Text(
                      formatCurrency(b.amount),
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  void _raiseBid(BuildContext context, ProductModel product, UserBid bid) {
    ThriftBottomSheet.show(
      context,
      title: 'Raise Bid',
      child: _RaiseBidContent(product: product, bid: bid),
    );
  }
}

class _RaiseBidContent extends StatefulWidget {
  final ProductModel product;
  final UserBid bid;

  const _RaiseBidContent({required this.product, required this.bid});

  @override
  State<_RaiseBidContent> createState() => _RaiseBidContentState();
}

class _RaiseBidContentState extends State<_RaiseBidContent> {
  late double minBid;
  late double selectedBid;
  final TextEditingController _customAmountController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final highest = widget.product.currentBid ?? widget.bid.amount;
    minBid = highest + widget.product.bidIncrement;
    selectedBid = minBid;
    _customAmountController.text = minBid.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  void _onQuickAmountTap(double amount) {
    setState(() {
      selectedBid = amount;
      _customAmountController.text = amount.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAmount = double.tryParse(_customAmountController.text) ?? 0.0;
    final isError = currentAmount < minBid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product context
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: widget.product.imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.product.title,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Bid info
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Current highest:', style: AppTypography.body),
            Text(
              formatCurrency(widget.product.currentBid ?? widget.product.price),
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Your last bid:', style: AppTypography.body),
            Text(
              formatCurrency(widget.bid.amount),
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Input Amount
        Text('Your Bid Amount', style: AppTypography.label),
        const SizedBox(height: 8),
        TextField(
          controller: _customAmountController,
          keyboardType: TextInputType.number,
          style: AppTypography.subheading,
          decoration: InputDecoration(
            prefixText: '\u20B1 ',
            prefixStyle: AppTypography.subheading,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isError ? AppColors.error : AppColors.border,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isError ? AppColors.error : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isError ? AppColors.error : AppColors.primary,
                width: 2,
              ),
            ),
            errorText: isError
                ? 'Bid must be at least ${formatCurrency(minBid)}'
                : null,
          ),
          onChanged: (val) {
            setState(() {
              selectedBid = double.tryParse(val) ?? 0;
            });
          },
        ),
        const SizedBox(height: 16),

        // Quick selects
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickSelect(minBid),
            _buildQuickSelect(minBid + 100),
            _buildQuickSelect(minBid + 500),
          ],
        ),
        const SizedBox(height: 32),

        ThriftButton(
          label: _submitting ? 'Placing Bid...' : 'Confirm Bid',
          onPressed: isError || _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  final controller = context.read<BuyerBidsController>();
                  final ok = await controller.raiseBid(
                    auctionId: widget.bid.auctionId ?? widget.product.id,
                    amount: currentAmount,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    showThriftSnackBar(
                      context,
                      ok ? 'Bid placed successfully!' : 'Failed to place bid',
                      isError: !ok,
                    );
                  }
                },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQuickSelect(double amount) {
    final isSelected = selectedBid == amount;
    return ChoiceChip(
      label: Text(formatCurrency(amount)),
      selected: isSelected,
      onSelected: (_) => _onQuickAmountTap(amount),
      selectedColor: AppColors.primaryLight,
      checkmarkColor: AppColors.primary,
      labelStyle: AppTypography.caption.copyWith(
        color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
