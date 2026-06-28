import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../models/bid_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/bid_card.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerBidsTab extends StatefulWidget {
  const BuyerBidsTab({super.key});

  @override
  State<BuyerBidsTab> createState() => _BuyerBidsTabState();
}

class _BuyerBidsTabState extends State<BuyerBidsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Future<void>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFuture = Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadFuture = Future.delayed(const Duration(milliseconds: 800));
    });
    return _loadFuture;
  }



  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final buyerId = auth.user?.id ?? 'buyer_maya';

    final activeBidsCount = data.bidsForBuyer(buyerId, BidTab.active).length;
    final wonBidsCount = data.bidsForBuyer(buyerId, BidTab.won).length;
    final lostBidsCount = data.bidsForBuyer(buyerId, BidTab.lost).length;

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
                Text('Track your auction activity', style: AppTypography.caption),
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
                labelStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
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
                _bidList(data.bidsForBuyer(buyerId, BidTab.active), data, buyerId, BidTab.active),
                _bidList(data.bidsForBuyer(buyerId, BidTab.won), data, buyerId, BidTab.won),
                _bidList(data.bidsForBuyer(buyerId, BidTab.lost), data, buyerId, BidTab.lost),
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
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ThriftCard(
          child: Row(
            children: [
              const ShimmerBox(width: 72, height: 72, radius: 8),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
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

  Widget _bidList(List<UserBid> bids, DataProvider data, String buyerId, BidTab tab) {
    return FutureBuilder(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonList();
        }

        if (bids.isEmpty) {
          return EmptyState(
            icon: Icons.gavel,
            title: 'No bids here',
            message: tab == BidTab.active ? 'Start bidding on items you love!' : 'Check back later for updates.',
            actionLabel: tab == BidTab.active ? 'Browse Items' : null,
            onAction: () {},
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bids.length,
            itemBuilder: (_, i) {
              final bid = bids[i];
              final product = data.productById(bid.productId);
              if (product == null) return const SizedBox();

              Widget cardContent;

              if (tab == BidTab.won) {
                cardContent = ThriftCard(
                  padding: EdgeInsets.zero,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
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
                                placeholder: (_, _) => Container(color: AppColors.surfaceVariant),
                                errorWidget: (_, _, _) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Icon(Icons.image_outlined, color: AppColors.textHint),
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
                                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('Winning bid: ', style: AppTypography.caption),
                                      Text(formatCurrency(bid.amount), style: AppTypography.subheading),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'You won this auction! 🎉',
                                    style: AppTypography.caption.copyWith(color: AppColors.success),
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
                                placeholder: (_, _) => Container(color: AppColors.surfaceVariant),
                                errorWidget: (_, _, _) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Icon(Icons.image_outlined, color: AppColors.textHint),
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
                                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('Final price: ', style: AppTypography.caption),
                                      Text(
                                        formatCurrency(product.currentBid ?? product.price),
                                        style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('Your bid: ', style: AppTypography.caption),
                                      Text(
                                        formatCurrency(bid.amount),
                                        style: AppTypography.caption.copyWith(decoration: TextDecoration.lineThrough),
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
                          onPressed: () => context.push('/search'),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                cardContent = BidCard(
                  bid: bid,
                  product: product,
                  onTap: () => _showBidHistory(context, product, buyerId),
                  onRaiseBid: bid.status == BidStatus.outbid
                      ? () => _raiseBid(context, product, bid, buyerId)
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
      },
    );
  }

  void _showBidHistory(BuildContext context, ProductModel product, String buyerId) {
    final currentUserUsername = 'user***${buyerId.hashCode.abs() % 100}';
    
    ThriftBottomSheet.show(
      context,
      title: 'Bid History',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bidder', style: AppTypography.caption),
                Text('Amount', style: AppTypography.caption),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ...product.bidHistory.map<Widget>((b) {
            final isMe = b.username == currentUserUsername;
            return Container(
              color: isMe ? AppColors.primaryLight.withValues(alpha: 0.3) : Colors.transparent,
              child: ListTile(
                title: Row(
                  children: [
                    Text(
                      b.username,
                      style: AppTypography.body.copyWith(fontWeight: isMe ? FontWeight.w600 : FontWeight.w400),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'You',
                          style: AppTypography.caption.copyWith(color: Colors.white, fontSize: 10),
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
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _raiseBid(BuildContext context, ProductModel product, UserBid bid, String buyerId) {
    ThriftBottomSheet.show(
      context,
      title: 'Raise Bid',
      child: _RaiseBidContent(product: product, bid: bid, buyerId: buyerId),
    );
  }
}

class _RaiseBidContent extends StatefulWidget {
  final ProductModel product;
  final UserBid bid;
  final String buyerId;

  const _RaiseBidContent({
    required this.product,
    required this.bid,
    required this.buyerId,
  });

  @override
  State<_RaiseBidContent> createState() => _RaiseBidContentState();
}

class _RaiseBidContentState extends State<_RaiseBidContent> {
  late double minBid;
  late double selectedBid;
  final TextEditingController _customAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    minBid = (widget.product.currentBid ?? widget.product.price) + widget.product.bidIncrement;
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
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
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
            prefixText: '₱ ',
            prefixStyle: AppTypography.subheading,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isError ? AppColors.error : AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isError ? AppColors.error : AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isError ? AppColors.error : AppColors.primary, width: 2),
            ),
            errorText: isError ? 'Bid must be at least ${formatCurrency(minBid)}' : null,
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
          label: 'Confirm Bid',
          onPressed: isError ? null : () async {
            final ok = await context.read<DataProvider>().placeBid(
              productId: widget.product.id,
              buyerId: widget.buyerId,
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
      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
