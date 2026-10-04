import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/core/utils/stock_limits.dart';
import 'package:thriftline/models/address_model.dart';
import 'package:thriftline/models/cart_item_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

ProductModel _mockProduct({
  required String id,
  required String title,
  required double price,
  required String sellerId,
  required int stock,
}) {
  return ProductModel(
    id: id,
    title: title,
    description: 'High quality thrift item',
    price: price,
    imageUrls: const ['https://example.com/image.jpg'],
    category: ProductCategory.outerwear,
    condition: ProductCondition.good,
    sellerId: sellerId,
    sellerUsername: 'seller_ukay',
    sellerName: 'Ukay Thrift',
    sellerAvatar: '',
    sellerVerified: true,
    sellingType: SellingType.fixedPrice,
    status: ProductStatus.active,
    quantityAvailable: stock,
    createdAt: DateTime.now(),
  );
}

/// Interactive harness for the Buyer Multi-item Checkout flow
class _BuyerCheckoutIntegrationScreen extends StatefulWidget {
  const _BuyerCheckoutIntegrationScreen({
    required this.cartItems,
    required this.shippingAddress,
    required this.onOrderPlaced,
  });

  final List<CartItemModel> cartItems;
  final AddressModel shippingAddress;
  final void Function(OrderModel order) onOrderPlaced;

  @override
  State<_BuyerCheckoutIntegrationScreen> createState() =>
      _BuyerCheckoutIntegrationScreenState();
}

class _BuyerCheckoutIntegrationScreenState
    extends State<_BuyerCheckoutIntegrationScreen> {
  DeliveryMethod _selectedShipping = DeliveryMethod.standard;
  late final Map<String, int> _itemQuantities;

  @override
  void initState() {
    super.initState();
    _itemQuantities = {
      for (final item in widget.cartItems) item.id: item.quantity,
    };
  }

  double get _subtotal {
    double total = 0;
    for (final item in widget.cartItems) {
      final qty = _itemQuantities[item.id] ?? 1;
      total += item.price * qty;
    }
    return total;
  }

  double get _shippingFee => _selectedShipping.fee;
  double get _platformFee => (_subtotal * 0.02).clamp(10.0, 100.0);
  double get _grandTotal => _subtotal + _shippingFee + _platformFee;

  void _placeOrder() {
    final items = widget.cartItems.map((cartItem) {
      final qty = _itemQuantities[cartItem.id] ?? 1;
      return OrderLineItem(
        id: 'item-${cartItem.id}',
        title: cartItem.product?.title ?? 'Product',
        unitPrice: cartItem.price,
        quantity: qty,
        lineTotal: cartItem.price * qty,
        productId: cartItem.productId,
      );
    }).toList();

    final order = OrderModel(
      id: 'order-chk-001',
      orderNumber: 'TL-202610-001',
      productId: widget.cartItems.first.productId,
      buyerId: 'buyer-qa-1',
      sellerId: widget.cartItems.first.product?.sellerId ?? 'seller-1',
      productTitle: items.first.title,
      productImage: '',
      sellerName: 'Ukay Thrift',
      buyerName: 'QA Buyer',
      buyerAvatar: '',
      status: OrderStatus.paymentPending,
      paymentMethod: PaymentMethod.unpaid,
      amount: _subtotal,
      shippingFee: _shippingFee,
      platformFee: _platformFee,
      total: _grandTotal,
      createdAt: DateTime.now(),
      items: items,
      deliveryMethod: _selectedShipping,
      shippingAddress: widget.shippingAddress.formatted,
    );

    widget.onOrderPlaced(order);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout Summary')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.shippingAddress.recipientName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(widget.shippingAddress.phoneNumber),
                  Text(widget.shippingAddress.formatted),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Order Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            for (final item in widget.cartItems) ...[
              ThriftCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product?.title ?? 'Product',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(formatCurrency(item.price)),
                        ],
                      ),
                    ),
                    Text('Qty: ${_itemQuantities[item.id]}'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            const Text(
              'Shipping Option',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButton<DeliveryMethod>(
              key: const Key('checkout-shipping-dropdown'),
              value: _selectedShipping,
              isExpanded: true,
              items:
                  DeliveryMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(
                        '${method.label} (+${formatCurrency(method.fee)})',
                      ),
                    );
                  }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedShipping = val);
              },
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal:'),
                Text(formatCurrency(_subtotal)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Shipping Fee:'),
                Text(formatCurrency(_shippingFee)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Platform Fee (2%):'),
                Text(formatCurrency(_platformFee)),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Payment:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatCurrency(_grandTotal),
                  key: const Key('checkout-grand-total'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6C5CE7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ThriftButton(
              key: const Key('checkout-place-order-button'),
              label: 'Place Order',
              onPressed: _placeOrder,
            ),
          ],
        ),
      ),
    );
  }
}

void buyerCheckoutIntegrationTests() {
  qaGroup('Buyer Checkout Integration Flow', () {
    qaIntegrationTest('full order checkout flow with Davao delivery, fees & placement', (
      tester,
    ) async {
      // 1. Setup products and address
      final jacket = _mockProduct(
        id: 'prod-jacket-1',
        title: 'Vintage Denim Jacket',
        price: 850.0,
        sellerId: 'seller-ukay-1',
        stock: 3,
      );

      final shirt = _mockProduct(
        id: 'prod-shirt-2',
        title: 'Retro Graphic Tee',
        price: 350.0,
        sellerId: 'seller-ukay-1',
        stock: 5,
      );

      final cartItems = [
        CartItemModel(
          id: 'cart-1',
          userId: 'buyer-qa-1',
          productId: jacket.id,
          product: jacket,
          quantity: 1,
        ),
        CartItemModel(
          id: 'cart-2',
          userId: 'buyer-qa-1',
          productId: shirt.id,
          product: shirt,
          quantity: 2,
        ),
      ];

      const deliveryAddress = AddressModel(
        id: 'addr-davao-1',
        userId: 'buyer-qa-1',
        recipientName: 'Dexter Ramos',
        phoneNumber: '09171234567',
        streetAddress: 'Block 12 Lot 4, Sunflower St.',
        barangay: 'Bucana',
        city: 'Davao City',
        postalCode: '8000',
        landmark: 'Near Bucana Barangay Hall',
        isDefault: true,
      );

      // Verify delivery address contact validity rule
      expect(deliveryAddress.hasValidPhoneContact, isTrue);
      expect(
        deliveryAddress.formatted,
        'Block 12 Lot 4, Sunflower St., Bucana, Davao City, 8000',
      );

      OrderModel? placedOrder;

      // 2. Mount Checkout Screen
      await tester.pumpWidget(
        MaterialApp(
          home: _BuyerCheckoutIntegrationScreen(
            cartItems: cartItems,
            shippingAddress: deliveryAddress,
            onOrderPlaced: (order) => placedOrder = order,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Verify Initial Cost Breakdown:
      // Subtotal = 850 + (350 * 2) = 1550.0
      // Standard Shipping = 80.0
      // Platform fee = 1550 * 0.02 = 31.0
      // Total = 1661.0
      expect(find.text('Dexter Ramos'), findsOneWidget);
      expect(find.text('Vintage Denim Jacket'), findsOneWidget);
      expect(find.text('Retro Graphic Tee'), findsOneWidget);
      expect(find.text(formatCurrency(1661.0)), findsOneWidget);

      // 4. Change Shipping to Express (₱150)
      await tester.ensureVisible(find.byKey(const Key('checkout-shipping-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkout-shipping-dropdown')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Express').last);
      await tester.pumpAndSettle();

      // New Total = 1550 + 150 + 31 = 1731.0
      expect(find.text(formatCurrency(1731.0)), findsOneWidget);

      // 5. Place the Order
      await tester.ensureVisible(find.byKey(const Key('checkout-place-order-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkout-place-order-button')));
      await tester.pumpAndSettle();

      expect(placedOrder, isNotNull);
      expect(placedOrder!.buyerId, 'buyer-qa-1');
      expect(placedOrder!.status, OrderStatus.paymentPending);
      expect(placedOrder!.amount, 1550.0);
      expect(placedOrder!.shippingFee, 150.0);
      expect(placedOrder!.platformFee, 31.0);
      expect(placedOrder!.total, 1731.0);
      expect(placedOrder!.items.length, 2);
    });

    qaIntegrationTest('stock clamp & shortage prevents over-purchasing during checkout', (
      tester,
    ) async {
      // Requested 8 but seller only has 2 left
      final clamped = clampCartQuantity(8, 2);
      expect(clamped, 2);

      final shortageMessage = stockShortageMessage(
        title: 'Leather Boots',
        requested: 5,
        available: 2,
      );

      expect(
        shortageMessage,
        'Available stock has changed. Only 2 left of Leather Boots. Update the quantity and try again.',
      );

      final soldOutMessage = stockShortageMessage(
        title: 'Leather Boots',
        requested: 1,
        available: 0,
      );
      expect(soldOutMessage, 'Leather Boots is no longer available.');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    buyerCheckoutIntegrationTests();
  });
}
