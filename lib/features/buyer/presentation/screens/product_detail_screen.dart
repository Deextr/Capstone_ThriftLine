import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/countdown_timer.dart';
import '../../../../widgets/thrift_widgets.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _bidController = TextEditingController();
  int _imageIndex = 0;

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  void _showBidBottomSheet(BuildContext context, ProductModel product, double minBid) {
    _bidController.text = minBid.toStringAsFixed(0);
    ThriftBottomSheet.show(
      context,
      title: 'Place a Bid',
      child: StatefulBuilder(
        builder: (context, setStateSB) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Bid: ${formatCurrency(product.currentBid ?? 0)}', style: AppTypography.subheading),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final v = (double.tryParse(_bidController.text) ?? minBid) - product.bidIncrement;
                      if (v >= minBid) {
                        setStateSB(() => _bidController.text = v.toStringAsFixed(0));
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
                      final v = (double.tryParse(_bidController.text) ?? minBid) + product.bidIncrement;
                      setStateSB(() => _bidController.text = v.toStringAsFixed(0));
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
                  final amount = double.tryParse(_bidController.text) ?? minBid;
                  final buyerId = context.read<AuthProvider>().user?.id ?? 'buyer_maya';
                  final ok = await context.read<DataProvider>().placeBid(
                        productId: product.id,
                        buyerId: buyerId,
                        amount: amount,
                      );
                  if (context.mounted) {
                    Navigator.pop(context);
                    showThriftSnackBar(
                      context,
                      ok ? 'Bid placed successfully!' : 'Bid must be at least ${formatCurrency(minBid)}',
                      isError: !ok,
                    );
                  }
                },
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final product = data.productById(widget.productId);
    if (product == null) {
      return const Scaffold(body: Center(child: Text('Product not found')));
    }

    final minBid = (product.currentBid ?? product.startingBid ?? product.price) + product.bidIncrement;
    final isSaved = data.isSaved(product.id);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildBottomBar(context, product, minBid),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopStack(context, product, isSaved),
            
            // Give space for the overlapping card
            const SizedBox(height: 65),

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
                    style: AppTypography.heading.copyWith(fontSize: 22, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  
                  // Attributes Row
                  Row(
                    children: [
                      _buildAttributeBox('Size', product.size ?? 'N/A'),
                      const SizedBox(width: 8),
                      _buildAttributeBox('Condition', product.condition.label),
                      const SizedBox(width: 8),
                      _buildAttributeBox('Color', product.color ?? 'N/A'),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Seller Card
                  _buildSellerCard(product),
                  
                  const SizedBox(height: 16),
                  
                  // Description
                  _buildSectionCard('Description', Text(product.description, style: AppTypography.body.copyWith(color: AppColors.textSecondary))),
                  
                  const SizedBox(height: 16),
                  
                  // Recent Bids
                  if (product.hasActiveBid) _buildRecentBidsCard(product),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStack(BuildContext context, ProductModel product, bool isSaved) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Image Carousel
        SizedBox(
          height: 380,
          child: PageView(
            onPageChanged: (i) => setState(() => _imageIndex = i),
            children: product.imageUrls
                .map<Widget>(
                  (url) => CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, _) => Container(color: AppColors.surfaceVariant),
                    errorWidget: (_, _, _) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: Icon(Icons.image_not_supported_outlined, color: AppColors.textHint, size: 40),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),

        // Gradient overlay at top for icons visibility
        Positioned(
          top: 0, left: 0, right: 0,
          height: 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
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
              _CircularButton(
                icon: isSaved ? Icons.favorite : Icons.favorite_border,
                iconColor: isSaved ? AppColors.error : AppColors.textPrimary,
                onTap: () => context.read<DataProvider>().toggleSave(product.id),
              ),
              const SizedBox(width: 10),
              _CircularButton(
                icon: Icons.share_outlined,
                onTap: () => showThriftSnackBar(context, 'Link copied!'),
              ),
            ],
          ),
        ),

        // Timer Pill
        if (product.hasActiveBid && product.bidEndTime != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  CountdownTimer(
                    endTime: product.bidEndTime!,
                    style: AppTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          
        // Image Dots
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              product.imageUrls.length,
              (i) => Container(
                margin: const EdgeInsets.all(3),
                width: _imageIndex == i ? 8 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _imageIndex == i ? AppColors.primary : Colors.white.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),

        // Overlapping Bid/Price Card
        Positioned(
          bottom: -45,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  blurRadius: 10, offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.hasActiveBid) ...[
                      Row(
                        children: [
                          const Icon(Icons.gavel_rounded, color: AppColors.primary, size: 16),
                          const SizedBox(width: 6),
                          Text('Current Bid', style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(formatCurrency(product.currentBid ?? product.startingBid ?? 0), style: AppTypography.heading.copyWith(color: AppColors.primary, fontSize: 28)),
                      const SizedBox(height: 2),
                      Text('${product.bidCount} bids placed', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                    ] else ...[
                      Text('Price', style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(formatCurrency(product.price), style: AppTypography.heading.copyWith(color: AppColors.primary, fontSize: 28)),
                      const SizedBox(height: 2),
                      Text('Buy Now item', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!product.hasActiveBid && product.currentBid == null) ...[ 
                       // Fixed Price: Show dynamic savings.
                       Text('Original', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                       Text(formatCurrency(product.price * 1.2), style: AppTypography.subheading.copyWith(color: AppColors.textHint, decoration: TextDecoration.lineThrough)),
                       Text('Save ${formatCurrency(product.price * 0.2)}', style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                    ] else ...[
                       // Bidding: Just original.
                       Text('Original', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                       Text(formatCurrency(product.price), style: AppTypography.subheading.copyWith(color: AppColors.textHint, decoration: TextDecoration.lineThrough)),
                    ]
                  ],
                ),
              ],
            ),
          ),
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
            Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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
            Text('Seller', style: AppTypography.subheading.copyWith(fontWeight: FontWeight.bold)),
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
                          Text(product.sellerName, style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w600)),
                          if (product.sellerVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, color: AppColors.primary, size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star, color: AppColors.warning, size: 14),
                          const SizedBox(width: 4),
                          Text('4.8', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          const Icon(Icons.location_on_outlined, color: AppColors.textSecondary, size: 14),
                          const SizedBox(width: 4),
                          Text('Quezon City', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.primary, size: 22),
              ],
            ),
          ],
        ),
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
          Text(title, style: AppTypography.subheading.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildRecentBidsCard(ProductModel product) {
    return _buildSectionCard(
      'Recent Bids',
      Column(
        children: product.bidHistory.take(3).map<Widget>((b) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.username, style: AppTypography.body.copyWith(fontWeight: FontWeight.w500)),
                    Text('Just now', style: AppTypography.caption.copyWith(color: AppColors.textHint)),
                  ],
                ),
                Text(formatCurrency(b.amount), style: AppTypography.subheading.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ProductModel product, double minBid) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton.icon(
              onPressed: () => context.push(RouteNames.chat),
              icon: const Icon(Icons.chat_bubble_outline, color: AppColors.textPrimary, size: 20),
              label: Text('Chat', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 16)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: const BorderSide(color: AppColors.border, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: ElevatedButton.icon(
              onPressed: () {
                if (product.hasActiveBid) {
                  _showBidBottomSheet(context, product, minBid);
                } else {
                  context.push('/buy-now/${product.id}');
                }
              },
              icon: Icon(product.hasActiveBid ? Icons.gavel_rounded : Icons.shopping_bag_outlined, color: Colors.white, size: 20),
              label: Text(product.hasActiveBid ? 'Place Bid' : 'Buy Now', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularButton extends StatelessWidget {
  const _CircularButton({required this.icon, required this.onTap, this.iconColor});
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 22),
      ),
    );
  }
}
