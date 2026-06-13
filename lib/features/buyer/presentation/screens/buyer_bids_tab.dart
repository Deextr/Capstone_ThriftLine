import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
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
    final buyerId = auth.user?.id ?? 'buyer_maya';

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Text('My Bids', style: AppTypography.heading),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Active Bids'),
              Tab(text: 'Won'),
              Tab(text: 'Lost'),
            ],
          ),
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

  Widget _bidList(List bids, DataProvider data, String buyerId, BidTab tab) {
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
      onRefresh: () async => setState(() {}),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bids.length,
        itemBuilder: (_, i) {
          final bid = bids[i];
          final product = data.productById(bid.productId);
          if (product == null) return const SizedBox();
          if (tab == BidTab.won) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ThriftCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(imageUrl: product.imageUrl, width: 60, height: 60, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.title, style: AppTypography.subheading),
                            Text('Congratulations! 🎉', style: AppTypography.caption.copyWith(color: AppColors.success)),
                          ],
                        )),
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
          }
          if (tab == BidTab.lost) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ThriftCard(
                child: Column(
                  children: [
                    Text(product.title, style: AppTypography.subheading),
                    Text('Better luck next time', style: AppTypography.caption),
                    const SizedBox(height: 8),
                    ThriftButton(label: 'Find Similar', variant: ThriftButtonVariant.outline, onPressed: () => context.push('/search')),
                  ],
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BidCard(
              bid: bid,
              product: product,
              onTap: () => _showBidHistory(context, product),
              onRaiseBid: bid.status == BidStatus.outbid
                  ? () => _raiseBid(context, product, bid, buyerId)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _showBidHistory(BuildContext context, product) {
    ThriftBottomSheet.show(
      context,
      title: 'Bid History',
      child: Column(
        children: product.bidHistory.map<Widget>((b) => ListTile(
          title: Text(b.username),
          trailing: Text(formatCurrency(b.amount), style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
        )).toList(),
      ),
    );
  }

  void _raiseBid(BuildContext context, product, bid, String buyerId) {
    final minBid = (product.currentBid ?? product.price) + product.bidIncrement;
    ThriftBottomSheet.show(
      context,
      title: 'Raise Bid',
      child: Column(
        children: [
          Text('Minimum bid: ${formatCurrency(minBid)}', style: AppTypography.body),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Bid ${formatCurrency(minBid)}',
            variant: ThriftButtonVariant.secondary,
            onPressed: () async {
              final ok = await context.read<DataProvider>().placeBid(
                productId: product.id,
                buyerId: buyerId,
                amount: minBid,
              );
              if (context.mounted) {
                Navigator.pop(context);
                showThriftSnackBar(context, ok ? 'Bid placed successfully!' : 'Failed to place bid', isError: !ok);
              }
            },
          ),
        ],
      ),
    );
  }
}
