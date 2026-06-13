import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyNowScreen extends StatefulWidget {
  const BuyNowScreen({super.key, required this.productId});

  final String productId;

  @override
  State<BuyNowScreen> createState() => _BuyNowScreenState();
}

class _BuyNowScreenState extends State<BuyNowScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final product = data.productById(widget.productId);
    if (product == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final subtotal = product.price * _quantity;
    const shipping = 80.0;
    final platform = subtotal * 0.02;
    final total = subtotal + shipping + platform;

    return Scaffold(
      appBar: AppBar(title: const Text('Buy Now'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
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
                      child: CachedNetworkImage(imageUrl: product.imageUrl, width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.title, style: AppTypography.subheading),
                          Text(product.sellerName, style: AppTypography.caption),
                          Text(formatCurrency(product.price), style: AppTypography.subheading.copyWith(color: const Color(0xFF0D9488))),
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
                  Text('Quantity', style: AppTypography.body),
                  Row(
                    children: [
                      IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove)),
                      Text('$_quantity', style: AppTypography.subheading),
                      IconButton(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add)),
                    ],
                  ),
                ],
              ),
              if (product.size != null)
                ListTile(
                  title: Text('Size: ${product.size}', style: AppTypography.body),
                  trailing: const Icon(Icons.check_circle, color: Color(0xFF0D9488)),
                ),
              const Divider(),
              _row('Subtotal', formatCurrency(subtotal)),
              _row('Shipping fee', formatCurrency(shipping)),
              _row('Platform fee (2%)', formatCurrency(platform)),
              const Divider(),
              _row('Total', formatCurrency(total), bold: true),
              const Spacer(),
              ThriftButton(
                label: 'Continue to Payment',
                onPressed: () => context.push('/payment/${product.id}?qty=$_quantity'),
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
            Text(label, style: bold ? AppTypography.subheading : AppTypography.body),
            Text(value, style: bold ? AppTypography.subheading.copyWith(color: const Color(0xFF0D9488)) : AppTypography.body),
          ],
        ),
      );
}
