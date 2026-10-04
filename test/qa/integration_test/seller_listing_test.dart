import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/core/utils/seller_trust.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Form harness simulating the seller listing creation flow
class _SellerListingCreationHarness extends StatefulWidget {
  const _SellerListingCreationHarness({
    required this.isVerifiedSeller,
    required this.onListingCreated,
  });

  final bool isVerifiedSeller;
  final void Function(ProductModel product) onListingCreated;

  @override
  State<_SellerListingCreationHarness> createState() =>
      _SellerListingCreationHarnessState();
}

class _SellerListingCreationHarnessState
    extends State<_SellerListingCreationHarness> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  ProductCategory _category = ProductCategory.tops;
  ProductCondition _condition = ProductCondition.likeNew;
  SellingType _sellingType = SellingType.fixedPrice;
  String? _errorNotice;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _errorNotice = null);

    if (!widget.isVerifiedSeller && _sellingType == SellingType.auction) {
      setState(() {
        _errorNotice = 'You must be identity-verified to host auctions.';
      });
      return;
    }

    if (_formKey.currentState!.validate()) {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final qty = int.tryParse(_quantityController.text) ?? 1;

      final product = ProductModel(
        id: 'prod-new-001',
        title: _titleController.text.trim(),
        description: 'Seller provided listing description',
        price: price,
        imageUrls: const ['https://example.com/item.jpg'],
        category: _category,
        condition: _condition,
        sellerId: 'seller-id-101',
        sellerUsername: 'seller_thrift',
        sellerName: 'Thrift Seller',
        sellerAvatar: '',
        sellerVerified: widget.isVerifiedSeller,
        sellingType: _sellingType,
        status: ProductStatus.active,
        quantityAvailable: _sellingType == SellingType.auction ? 1 : qty,
        createdAt: DateTime.now(),
      );

      widget.onListingCreated(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Product Listing')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorNotice != null)
                Container(
                  key: const Key('listing-error-banner'),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.red.shade100,
                  child: Text(
                    _errorNotice!,
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              ThriftTextField(
                key: const Key('listing-title-input'),
                label: 'Item Title',
                controller: _titleController,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter title' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProductCategory>(
                key: const Key('listing-category-dropdown'),
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items:
                    ProductCategory.values.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c.label));
                    }).toList(),
                onChanged: (c) {
                  if (c != null) setState(() => _category = c);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProductCondition>(
                key: const Key('listing-condition-dropdown'),
                value: _condition,
                decoration: const InputDecoration(labelText: 'Condition'),
                items:
                    ProductCondition.values.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c.label));
                    }).toList(),
                onChanged: (c) {
                  if (c != null) setState(() => _condition = c);
                },
              ),
              const SizedBox(height: 12),
              const Text('Listing Format:'),
              Row(
                children: [
                  ChoiceChip(
                    key: const Key('format-fixed'),
                    label: const Text('Fixed Price'),
                    selected: _sellingType == SellingType.fixedPrice,
                    onSelected:
                        (_) => setState(() => _sellingType = SellingType.fixedPrice),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const Key('format-auction'),
                    label: const Text('Auction'),
                    selected: _sellingType == SellingType.auction,
                    onSelected:
                        (_) => setState(() => _sellingType = SellingType.auction),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('listing-price-input'),
                label: _sellingType == SellingType.auction ? 'Starting Bid (₱)' : 'Price (₱)',
                controller: _priceController,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
              if (_sellingType == SellingType.fixedPrice) ...[
                const SizedBox(height: 12),
                ThriftTextField(
                  key: const Key('listing-quantity-input'),
                  label: 'Quantity In Stock',
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final parsed = int.tryParse(v ?? '');
                    if (parsed == null || parsed < 1) return 'Must be 1 or more';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24),
              ThriftButton(
                key: const Key('listing-publish-button'),
                label: 'Publish Listing',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _listingInput(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);

void sellerListingIntegrationTests() {
  qaGroup('Seller Listing Integration Flow', () {
    qaIntegrationTest('verified seller creates fixed-price product successfully', (
      tester,
    ) async {
      ProductModel? createdProduct;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerListingCreationHarness(
            isVerifiedSeller: true,
            onListingCreated: (prod) => createdProduct = prod,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in details for a fixed price jacket
      await tester.enterText(_listingInput('listing-title-input'), 'Vintage Leather Jacket');
      await tester.enterText(_listingInput('listing-price-input'), '1800');
      await tester.enterText(_listingInput('listing-quantity-input'), '2');

      // Change category to Outerwear
      await tester.tap(find.byKey(const Key('listing-category-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outerwear').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('listing-publish-button')));
      await tester.pumpAndSettle();

      expect(createdProduct, isNotNull);
      expect(createdProduct!.title, 'Vintage Leather Jacket');
      expect(createdProduct!.price, 1800.0);
      expect(createdProduct!.quantityAvailable, 2);
      expect(createdProduct!.category, ProductCategory.outerwear);
      expect(createdProduct!.condition, ProductCondition.likeNew);
      expect(createdProduct!.sellingType, SellingType.fixedPrice);
      expect(createdProduct!.status, ProductStatus.active);
    });

    qaIntegrationTest('unverified seller is blocked from hosting auctions', (
      tester,
    ) async {
      ProductModel? createdProduct;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerListingCreationHarness(
            isVerifiedSeller: false, // Not verified
            onListingCreated: (prod) => createdProduct = prod,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_listingInput('listing-title-input'), 'Rare Vintage Cap');
      await tester.enterText(_listingInput('listing-price-input'), '500');

      // Switch to Auction
      await tester.tap(find.byKey(const Key('format-auction')));
      await tester.pumpAndSettle();

      // Attempt to publish
      await tester.tap(find.byKey(const Key('listing-publish-button')));
      await tester.pumpAndSettle();

      expect(createdProduct, isNull);
      expect(
        find.text('You must be identity-verified to host auctions.'),
        findsOneWidget,
      );
    });

    qaIntegrationTest('seller trust label is classified according to trust criteria', (
      tester,
    ) async {
      // Verified seller with 92 score
      expect(resolveTrustLabel(score: 92), 'Highly Trusted Seller');
      // Established seller with 80 score
      expect(resolveTrustLabel(score: 80), 'Trusted Seller');
      // New seller with 65 score
      expect(resolveTrustLabel(score: 65), 'New Seller');
      // Under Review
      expect(resolveTrustLabel(score: 45), 'Under Review');
      // Banned
      expect(resolveTrustLabel(score: 20), 'Banned');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    sellerListingIntegrationTests();
  });
}
