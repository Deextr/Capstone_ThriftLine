import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/countdown_timer.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _bidController = TextEditingController();
  bool _expanded = false;
  bool _showBidHistory = false;
  int _imageIndex = 0;

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final product = data.productById(widget.productId);
    if (product == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Product not found')));
    }

    final minBid = (product.currentBid ?? product.startingBid ?? product.price) + product.bidIncrement;
    _bidController.text = minBid.toStringAsFixed(0);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
                actions: [
                  IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => showThriftSnackBar(context, 'Link copied!')),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 300,
                      child: PageView(
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        children: product.imageUrls.map((url) => CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(color: AppColors.primaryLight),
                        )).toList(),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(product.imageUrls.length, (i) => Container(
                        margin: const EdgeInsets.all(3),
                        width: _imageIndex == i ? 8 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _imageIndex == i ? AppColors.primary : AppColors.border,
                          shape: BoxShape.circle,
                        ),
                      )),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppConstants.spacingMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.title, style: AppTypography.heading),
                          const SizedBox(height: 8),
                          Text(formatCurrency(product.displayPrice), style: AppTypography.display.copyWith(color: AppColors.primary, fontSize: 24)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ThriftBadge(label: product.category.label),
                              ThriftBadge(label: product.condition.label, variant: BadgeVariant.neutral),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ThriftCard(
                            child: Row(
                              children: [
                                ThriftAvatar(imageUrl: product.sellerAvatar, size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(product.sellerName, style: AppTypography.subheading),
                                          if (product.sellerVerified) const Icon(Icons.verified, size: 16, color: AppColors.primary),
                                        ],
                                      ),
                                      Text('⭐ 4.8 • View Shop', style: AppTypography.caption.copyWith(color: AppColors.primary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _expanded ? product.description : '${product.description.substring(0, product.description.length.clamp(0, 80))}...',
                            style: AppTypography.body,
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Text(_expanded ? 'Show less' : 'Read more', style: AppTypography.body.copyWith(color: AppColors.primary)),
                          ),
                          const SizedBox(height: 16),
                          _detailGrid(product),
                          if (product.hasActiveBid) ...[
                            const SizedBox(height: 16),
                            ThriftCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Bid: ${formatCurrency(product.currentBid ?? 0)}', style: AppTypography.subheading.copyWith(color: AppColors.secondary)),
                                  if (product.bidEndTime != null)
                                    CountdownTimer(endTime: product.bidEndTime!),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          final v = (double.tryParse(_bidController.text) ?? minBid) - product.bidIncrement;
                                          _bidController.text = v.toStringAsFixed(0);
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.remove_circle_outline),
                                      ),
                                      Expanded(child: ThriftTextField(controller: _bidController, keyboardType: TextInputType.number)),
                                      IconButton(
                                        onPressed: () {
                                          final v = (double.tryParse(_bidController.text) ?? minBid) + product.bidIncrement;
                                          _bidController.text = v.toStringAsFixed(0);
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.add_circle_outline),
                                      ),
                                    ],
                                  ),
                                  ThriftButton(
                                    label: 'Place Bid',
                                    variant: ThriftButtonVariant.secondary,
                                    onPressed: () => _confirmBid(context, product, minBid),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Starting: ${formatCurrency(product.startingBid ?? product.price)} • Increment: ${formatCurrency(product.bidIncrement)}', style: AppTypography.caption),
                                  GestureDetector(
                                    onTap: () => setState(() => _showBidHistory = !_showBidHistory),
                                    child: Text('Bid History', style: AppTypography.body.copyWith(color: AppColors.primary)),
                                  ),
                                  if (_showBidHistory)
                                    ...product.bidHistory.take(5).map((b) => ListTile(
                                      dense: true,
                                      title: Text(b.username, style: AppTypography.caption),
                                      trailing: Text(formatCurrency(b.amount)),
                                    )),
                                ],
                              ),
                            ),
                          ],
                          if (product.buyNowEnabled) ...[
                            const SizedBox(height: 16),
                            ThriftButton(
                              label: 'Buy Now: ${formatCurrency(product.price)}',
                              onPressed: () => context.push('/buy-now/${product.id}'),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(data.isSaved(product.id) ? Icons.favorite : Icons.favorite_border, color: AppColors.error),
                                onPressed: () => data.toggleSave(product.id),
                              ),
                              IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
                              IconButton(icon: const Icon(Icons.chat_bubble_outline), onPressed: () => context.push(RouteNames.chat)),
                              IconButton(icon: const Icon(Icons.flag_outlined), onPressed: () => showThriftSnackBar(context, 'Report submitted')),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('Similar Items', style: AppTypography.heading),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 220,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: data.products.where((p) => p.category == product.category && p.id != product.id).take(5).length,
                              itemBuilder: (_, i) {
                                final similar = data.products.where((p) => p.category == product.category && p.id != product.id).toList()[i];
                                return SizedBox(
                                  width: 150,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ProductCard(product: similar, onTap: () => context.push('/product/${similar.id}')),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailGrid(product) {
    final items = {
      'Size': product.size ?? 'N/A',
      'Brand': product.brand ?? 'N/A',
      'Color': product.color ?? 'N/A',
      'Material': product.material ?? 'N/A',
    };
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3,
      children: items.entries.map((e) => ThriftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(e.key, style: AppTypography.caption),
            Text(e.value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      )).toList(),
    );
  }

  void _confirmBid(BuildContext context, product, double minBid) {
    final amount = double.tryParse(_bidController.text) ?? minBid;
    ThriftBottomSheet.show(
      context,
      title: 'Confirm Bid',
      child: Column(
        children: [
          Text('Place bid of ${formatCurrency(amount)} on ${product.title}?', style: AppTypography.body, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Confirm Bid',
            variant: ThriftButtonVariant.secondary,
            onPressed: () async {
              final buyerId = context.read<AuthProvider>().user?.id ?? 'buyer_maya';
              final ok = await context.read<DataProvider>().placeBid(
                productId: product.id,
                buyerId: buyerId,
                amount: amount,
              );
              if (context.mounted) {
                Navigator.pop(context);
                showThriftSnackBar(context, ok ? 'Bid placed successfully!' : 'Bid must be at least ${formatCurrency(minBid)}', isError: !ok);
              }
            },
          ),
        ],
      ),
    );
  }
}
