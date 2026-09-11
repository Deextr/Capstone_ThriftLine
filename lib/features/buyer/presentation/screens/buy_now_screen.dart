import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/stock_limits.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/catalog_product_query.dart';
import '../../data/checkout_totals.dart';

class BuyNowScreen extends StatefulWidget {
  const BuyNowScreen({super.key, required this.productId});

  final String productId;

  @override
  State<BuyNowScreen> createState() => _BuyNowScreenState();
}

class _BuyNowScreenState extends State<BuyNowScreen> {
  int _quantity = 1;
  ProductModel? _product;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    try {
      final client = context.read<SupabaseService>().client;
      final rows = await runProductCatalogSelect((select) {
        return client
            .from('products')
            .select(select)
            .eq('product_id', widget.productId)
            .limit(1);
      });
      final list = rows as List;
      if (list.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Listing not found.';
        });
        return;
      }
      final row = list.first as Map<String, dynamic>;
      final sellerId = row['seller_id'] as String?;
      final profiles = await fetchSellerProfilesMap(
        client,
        extraSellerIds: [?sellerId],
        includeApproved: false,
      );
      final products = hydrateCatalogProducts(list, profiles);
      final product = products.isEmpty ? null : products.first;
      var quantity = 1;
      if (product != null) {
        final max = product.maxPurchasableQuantity;
        quantity = max <= 0 ? 1 : clampCartQuantity(1, max);
      }
      setState(() {
        _product = product;
        _quantity = quantity < 1 ? 1 : quantity;
        _loading = false;
        _error = product == null ? 'Listing not found.' : null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load this listing.';
      });
    }
  }

  Future<void> _continue() async {
    final product = _product;
    if (product == null || _submitting) return;
    if (product.sellingType == SellingType.auction) {
      showThriftSnackBar(
        context,
        'Auction wins appear as pending orders on the Bids tab.',
        isError: true,
      );
      return;
    }
    final max = product.maxPurchasableQuantity;
    if (max <= 0) {
      showThriftSnackBar(
        context,
        '${product.title} is no longer available.',
        isError: true,
      );
      return;
    }
    final requested = _quantity;
    final quantity = clampCartQuantity(requested, max);
    if (quantity <= 0 || requested > max) {
      setState(() => _quantity = quantity <= 0 ? 1 : quantity);
      showThriftSnackBar(
        context,
        stockShortageMessage(
              title: product.title,
              requested: requested,
              available: max,
            ) ??
            'Only $max left of ${product.title}.',
        isError: true,
      );
      return;
    }
    setState(() => _submitting = true);
    final cart = context.read<CartProvider>();
    if (cart.isInCart(product.id)) {
      await cart.updateQuantity(product.id, quantity);
    } else {
      await cart.addToCart(product, quantity: quantity);
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    context.push('${RouteNames.checkout}?product=${product.id}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final product = _product;
    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error ?? 'Not found')),
      );
    }

    final subtotal = product.price * _quantity;
    final shipping = checkoutShippingFee(1);
    final platform = checkoutPlatformFee(subtotal);
    final total = checkoutTotal(
      subtotal: subtotal,
      shippingFee: shipping,
      platformFee: platform,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy Now'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Column(
            children: [
              ThriftCard(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: const Color(0xFFF1F5F9)),
                        errorWidget: (_, _, _) => Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.title, style: AppTypography.subheading),
                          Text(
                            product.sellerName,
                            style: AppTypography.caption,
                          ),
                          Text(
                            formatCurrency(product.price),
                            style: AppTypography.subheading.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quantity', style: AppTypography.body),
                      if (product.maxPurchasableQuantity > 0)
                        Text(
                          product.maxPurchasableQuantity == 1
                              ? '1 left'
                              : '${product.maxPurchasableQuantity} left',
                          style: AppTypography.caption,
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('$_quantity', style: AppTypography.subheading),
                      IconButton(
                        onPressed: _quantity < product.maxPurchasableQuantity
                            ? () => setState(() => _quantity++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              _row('Subtotal', formatCurrency(subtotal)),
              _row('Shipping fee', formatCurrency(shipping)),
              _row('Platform fee (2%)', formatCurrency(platform)),
              const Divider(),
              _row('Total', formatCurrency(total), bold: true),
              const Spacer(),
              ThriftButton(
                label: product.maxPurchasableQuantity <= 0
                    ? 'Sold out'
                    : 'Continue to checkout',
                isLoading: _submitting,
                onPressed: _submitting || product.maxPurchasableQuantity <= 0
                    ? null
                    : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: bold ? AppTypography.subheading : AppTypography.body,
        ),
        Text(
          value,
          style: bold
              ? AppTypography.subheading.copyWith(color: AppColors.primary)
              : AppTypography.body,
        ),
      ],
    ),
  );
}
