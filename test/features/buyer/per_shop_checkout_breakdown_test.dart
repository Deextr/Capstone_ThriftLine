import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/buyer/controllers/buyer_orders_controller.dart';
import 'package:thriftline/features/buyer/data/cart_shop_group.dart';
import 'package:thriftline/features/buyer/data/checkout_totals.dart';
import 'package:thriftline/features/buyer/presentation/widgets/cart_checkout_shop_section.dart';
import 'package:thriftline/features/buyer/presentation/widgets/order_cost_breakdown_section.dart';
import 'package:thriftline/features/buyer/presentation/widgets/payment_checkout_body.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/providers/auth_provider.dart';
import 'package:thriftline/providers/cart_provider.dart';

ProductModel _mockProduct({
  required String id,
  required String sellerId,
  required String sellerName,
  required double price,
  double shippingFee = 80,
  String shippingMode = 'fixed_fee',
  int? freeShippingQtyThreshold,
  String? size,
}) {
  return ProductModel.fromSupabase(
    {
      'product_id': id,
      'seller_id': sellerId,
      'name': 'Item $id',
      'price': price,
      'condition': 'good',
      'listing_type': 'fixed_price',
      'status': 'active',
      'quantity_available': 10,
      'shipping_mode': shippingMode,
      'shipping_fee': shippingFee,
      'free_shipping_qty_threshold': freeShippingQtyThreshold,
      'size': size,
    },
    sellerProfile: {
      'shop_name': sellerName,
      'is_approved': true,
      'user': {'user_id': sellerId, 'username': sellerName},
    },
  );
}

OrderModel _mockOrder({
  required String id,
  required String sellerId,
  required String sellerName,
  required double subtotal,
  required double shippingFee,
  required double platformFee,
  required double total,
  required List<OrderLineItem> items,
  String orderNumber = 'TL-001',
}) {
  return OrderModel(
    id: id,
    orderNumber: orderNumber,
    productId: items.isNotEmpty ? (items.first.productId ?? '') : '',
    buyerId: 'buyer-1',
    sellerId: sellerId,
    productTitle: items.isNotEmpty ? items.first.title : 'Order Item',
    productImage: items.isNotEmpty ? (items.first.imageUrl ?? '') : '',
    sellerName: sellerName,
    buyerName: 'Buyer One',
    buyerAvatar: '',
    amount: subtotal,
    shippingFee: shippingFee,
    platformFee: platformFee,
    total: total,
    status: OrderStatus.paymentPending,
    paymentMethod: PaymentMethod.unpaid,
    deliveryMethod: DeliveryMethod.standard,
    shippingAddress: '123 Test St, Metro Manila',
    deliveryPhone: '09171234567',
    createdAt: DateTime(2026, 10, 8),
    items: items,
  );
}

class _MockAuthProvider extends Fake with ChangeNotifier implements AuthProvider {
  @override
  AuthUser? get user => const AuthUser(
        id: 'buyer-1',
        email: 'buyer@test.com',
        username: 'buyer1',
        name: 'Buyer One',
        role: UserRole.buyer,
        avatarUrl: '',
        location: '',
      );
}

class _MockBuyerOrdersController extends Fake with ChangeNotifier
    implements BuyerOrdersController {
  @override
  bool get isStartingPayment => false;
}

void main() {
  group('Per-Shop Financial Breakdown & Math Reconciliation', () {
    test('1. One Shop, One Product', () {
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Vintage Thrift',
        price: 350.0,
        shippingFee: 80.0,
      );

      final items = [CartItem(product: p1, quantity: 1)];
      final groups = groupCartItemsByShop(items);

      expect(groups.length, 1);
      final shop1 = groups.first;
      expect(shop1.shopName, 'Vintage Thrift');
      expect(shop1.subtotal, 350.0);
      expect(shop1.shippingFee, 80.0);
      expect(shop1.platformFee, 7.0); // 2% of 350 = 7.0
      expect(shop1.total, 437.0); // 350 + 80 + 7 = 437.0

      // Reconciles with combined totals
      expect(checkoutGroupsSubtotal(groups), 350.0);
      expect(checkoutGroupsShipping(groups), 80.0);
      expect(checkoutGroupsPlatformFee(groups), 7.0);
      expect(checkoutGroupsTotal(groups), 437.0);
      expect(
        checkoutGroupsSubtotal(groups) +
            checkoutGroupsShipping(groups) +
            checkoutGroupsPlatformFee(groups),
        checkoutGroupsTotal(groups),
      );
    });

    test('2. One Shop, Multiple Products', () {
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Retro Kicks',
        price: 500.0,
        shippingFee: 80.0,
      );
      final p2 = _mockProduct(
        id: 'p2',
        sellerId: 's1',
        sellerName: 'Retro Kicks',
        price: 250.0,
        shippingFee: 80.0,
      );

      final items = [
        CartItem(product: p1, quantity: 1),
        CartItem(product: p2, quantity: 2), // 2 * 250 = 500
      ];
      final groups = groupCartItemsByShop(items);

      expect(groups.length, 1);
      final shop = groups.first;
      expect(shop.quantity, 3);
      expect(shop.subtotal, 1000.0);
      // Shipping fee is per shop/order, not charged per product line
      expect(shop.shippingFee, 80.0);
      // Platform fee is 2% of the order subtotal
      expect(shop.platformFee, 20.0); // 2% of 1000 = 20.0
      expect(shop.total, 1100.0); // 1000 + 80 + 20 = 1100.0

      expect(checkoutGroupsTotal(groups), 1100.0);
    });

    test('3. Two Shops, One Product Each', () {
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Shop Alpha',
        price: 450.0,
        shippingFee: 80.0,
      );
      final p2 = _mockProduct(
        id: 'p2',
        sellerId: 's2',
        sellerName: 'Shop Beta',
        price: 600.0,
        shippingFee: 100.0,
      );

      final items = [
        CartItem(product: p1, quantity: 1),
        CartItem(product: p2, quantity: 1),
      ];
      final groups = groupCartItemsByShop(items);

      expect(groups.length, 2);

      final alpha = groups.firstWhere((g) => g.shopName == 'Shop Alpha');
      expect(alpha.subtotal, 450.0);
      expect(alpha.shippingFee, 80.0);
      expect(alpha.platformFee, 9.0); // 2% of 450 = 9.0
      expect(alpha.total, 539.0); // 450 + 80 + 9 = 539.0

      final beta = groups.firstWhere((g) => g.shopName == 'Shop Beta');
      expect(beta.subtotal, 600.0);
      expect(beta.shippingFee, 100.0);
      expect(beta.platformFee, 12.0); // 2% of 600 = 12.0
      expect(beta.total, 712.0); // 600 + 100 + 12 = 712.0

      // Combined Payment Summary math reconciliation
      final combinedSubtotal = checkoutGroupsSubtotal(groups);
      final combinedShipping = checkoutGroupsShipping(groups);
      final combinedPlatform = checkoutGroupsPlatformFee(groups);
      final combinedTotal = checkoutGroupsTotal(groups);

      expect(combinedSubtotal, 1050.0); // 450 + 600
      expect(combinedShipping, 180.0); // 80 + 100
      expect(combinedPlatform, 21.0); // 9 + 12
      expect(combinedTotal, 1251.0); // 539 + 712

      // Sum of order totals == Combined Payment Total
      expect(alpha.total + beta.total, combinedTotal);
      // Combined Subtotal + Shipping + Platform == Combined Total
      expect(
        combinedSubtotal + combinedShipping + combinedPlatform,
        combinedTotal,
      );
    });

    test('4. Multiple Products From Multiple Shops with Free Shipping Threshold', () {
      // Shop 1: 2 items, fixed shipping 80
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Shop 1',
        price: 200.0,
      );
      final p2 = _mockProduct(
        id: 'p2',
        sellerId: 's1',
        sellerName: 'Shop 1',
        price: 300.0,
      );

      // Shop 2: 1 item, fixed shipping 80
      final p3 = _mockProduct(
        id: 'p3',
        sellerId: 's2',
        sellerName: 'Shop 2',
        price: 150.0,
      );

      // Shop 3: 2 items, qualifies for free shipping (threshold 2)
      final p4 = _mockProduct(
        id: 'p4',
        sellerId: 's3',
        sellerName: 'Shop 3',
        price: 400.0,
        shippingMode: 'quantity_threshold',
        shippingFee: 80.0,
        freeShippingQtyThreshold: 2,
      );
      final p5 = _mockProduct(
        id: 'p5',
        sellerId: 's3',
        sellerName: 'Shop 3',
        price: 400.0,
        shippingMode: 'quantity_threshold',
        shippingFee: 80.0,
        freeShippingQtyThreshold: 2,
      );

      final items = [
        CartItem(product: p1, quantity: 1),
        CartItem(product: p2, quantity: 1),
        CartItem(product: p3, quantity: 1),
        CartItem(product: p4, quantity: 1),
        CartItem(product: p5, quantity: 1),
      ];
      final groups = groupCartItemsByShop(items);
      expect(groups.length, 3);

      final shop1 = groups.firstWhere((g) => g.shopName == 'Shop 1');
      expect(shop1.subtotal, 500.0);
      expect(shop1.shippingFee, 80.0);
      expect(shop1.platformFee, 10.0);
      expect(shop1.total, 590.0);

      final shop2 = groups.firstWhere((g) => g.shopName == 'Shop 2');
      expect(shop2.subtotal, 150.0);
      expect(shop2.shippingFee, 80.0);
      expect(shop2.platformFee, 3.0);
      expect(shop2.total, 233.0);

      final shop3 = groups.firstWhere((g) => g.shopName == 'Shop 3');
      expect(shop3.subtotal, 800.0);
      expect(shop3.shippingFee, 0.0); // Met threshold of 2!
      expect(shop3.platformFee, 16.0);
      expect(shop3.total, 816.0);

      final combinedSubtotal = checkoutGroupsSubtotal(groups);
      final combinedShipping = checkoutGroupsShipping(groups);
      final combinedPlatform = checkoutGroupsPlatformFee(groups);
      final combinedTotal = checkoutGroupsTotal(groups);

      expect(combinedSubtotal, 1450.0);
      expect(combinedShipping, 160.0); // 80 + 80 + 0
      expect(combinedPlatform, 29.0); // 10 + 3 + 16
      expect(combinedTotal, 1639.0); // 590 + 233 + 816

      expect(shop1.total + shop2.total + shop3.total, combinedTotal);
      expect(
        combinedSubtotal + combinedShipping + combinedPlatform,
        combinedTotal,
      );
    });

    test('5. Exact Centavo Precision (No Floating Point Inaccuracies)', () {
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Shop A',
        price: 33.33,
      );
      final p2 = _mockProduct(
        id: 'p2',
        sellerId: 's2',
        sellerName: 'Shop B',
        price: 66.67,
      );

      final items = [
        CartItem(product: p1, quantity: 3), // 99.99
        CartItem(product: p2, quantity: 1), // 66.67
      ];
      final groups = groupCartItemsByShop(items);

      final a = groups.firstWhere((g) => g.shopName == 'Shop A');
      expect(a.subtotal, 99.99);
      expect(a.platformFee, 2.00); // round(99.99 * 0.02) = 2.00
      expect(a.total, 181.99); // 99.99 + 80 + 2.00

      final b = groups.firstWhere((g) => g.shopName == 'Shop B');
      expect(b.subtotal, 66.67);
      expect(b.platformFee, 1.33); // round(66.67 * 0.02) = 1.33
      expect(b.total, 148.00); // 66.67 + 80 + 1.33

      final combinedTotal = checkoutGroupsTotal(groups);
      expect(combinedTotal, 329.99); // 181.99 + 148.00
      expect(
        checkoutRoundCurrency(
          checkoutGroupsSubtotal(groups) +
              checkoutGroupsShipping(groups) +
              checkoutGroupsPlatformFee(groups),
        ),
        combinedTotal,
      );
    });
  });

  group('UI Components: OrderCostBreakdown & CombinedPaymentSummaryCard', () {
    testWidgets('OrderCostBreakdown renders all cost rows and formatted currency',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrderCostBreakdown(
              subtotal: 500.0,
              shippingFee: 80.0,
              platformFee: 10.0,
              total: 590.0,
              itemCount: 2,
            ),
          ),
        ),
      );

      expect(find.text('Item subtotal (2 items)'), findsOneWidget);
      expect(find.text(formatCurrency(500.0)), findsOneWidget);
      expect(find.text('Shipping fee'), findsOneWidget);
      expect(find.text(formatCurrency(80.0)), findsOneWidget);
      expect(find.text('Platform fee (2%)'), findsOneWidget);
      expect(find.text(formatCurrency(10.0)), findsOneWidget);
      expect(find.text('Order total'), findsOneWidget);
      expect(find.text(formatCurrency(590.0)), findsOneWidget);
    });

    testWidgets('OrderCostBreakdown displays Free for 0 shipping', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrderCostBreakdown(
              subtotal: 800.0,
              shippingFee: 0.0,
              platformFee: 16.0,
              total: 816.0,
            ),
          ),
        ),
      );

      expect(find.text('Item subtotal'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text(formatCurrency(816.0)), findsOneWidget);
    });

    testWidgets('CombinedPaymentSummaryCard aggregates and displays multi-shop info',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CombinedPaymentSummaryCard(
              subtotal: 1200.0,
              shippingFee: 160.0,
              platformFee: 24.0,
              total: 1384.0,
              shopCount: 2,
              itemCount: 3,
            ),
          ),
        ),
      );

      expect(find.text('Payment summary'), findsOneWidget);
      expect(find.text('2 shops · 1 payment'), findsOneWidget);
      expect(find.text('Items subtotal (3 items, 2 shops)'), findsOneWidget);
      expect(find.text(formatCurrency(1200.0)), findsOneWidget);
      expect(find.text('Shipping fee (2 shops)'), findsOneWidget);
      expect(find.text(formatCurrency(160.0)), findsOneWidget);
      expect(find.text('Platform fee (2%)'), findsOneWidget);
      expect(find.text(formatCurrency(24.0)), findsOneWidget);
      expect(find.text('Total payment'), findsOneWidget);
      expect(find.text(formatCurrency(1384.0)), findsOneWidget);
      expect(
        find.text(
          'Includes 2 orders from 2 separate shops. You pay once securely through PayMongo.',
        ),
        findsOneWidget,
      );
    });
  });

  group('CartCheckoutShopSection with breakdown in checkoutReview mode', () {
    testWidgets('Displays order index badge and OrderCostBreakdown',
        (tester) async {
      final p1 = _mockProduct(
        id: 'p1',
        sellerId: 's1',
        sellerName: 'Thrift Haven',
        price: 250.0,
      );
      final group = CartShopGroup(
        sellerKey: 's1',
        shopName: 'Thrift Haven',
        sellerUsername: 'thrifthaven',
        sellerVerified: true,
        items: [CartItem(product: p1, quantity: 2)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CartCheckoutShopSection(
              shop: group,
              mode: CartLineInteractionMode.checkoutReview,
              orderIndex: 0,
              totalOrders: 2,
            ),
          ),
        ),
      );

      expect(find.text('Thrift Haven'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(find.text('Order 1 of 2'), findsOneWidget);
      expect(find.text('Item subtotal (2 items)'), findsOneWidget);
      expect(find.text(formatCurrency(500.0)), findsOneWidget);
      expect(find.text('Shipping fee'), findsOneWidget);
      expect(find.text(formatCurrency(80.0)), findsOneWidget);
      expect(find.text('Platform fee (2%)'), findsOneWidget);
      expect(find.text(formatCurrency(10.0)), findsOneWidget);
      expect(find.text('Order total'), findsOneWidget);
      expect(find.text(formatCurrency(590.0)), findsOneWidget);
    });
  });

  group('PaymentCheckoutBody with multi-shop OrderModel breakdown', () {
    testWidgets('renders each seller order breakdown and combined payment summary',
        (tester) async {
      final order1 = _mockOrder(
        id: 'order-1',
        orderNumber: 'TL-20261008-01',
        sellerId: 'seller-a',
        sellerName: 'Seller Alpha',
        subtotal: 500.0,
        shippingFee: 80.0,
        platformFee: 10.0,
        total: 590.0,
        items: const [
          OrderLineItem(
            id: 'li-1',
            title: 'Vintage Jacket',
            unitPrice: 500.0,
            quantity: 1,
            lineTotal: 500.0,
          ),
        ],
      );

      final order2 = _mockOrder(
        id: 'order-2',
        orderNumber: 'TL-20261008-02',
        sellerId: 'seller-b',
        sellerName: 'Seller Beta',
        subtotal: 300.0,
        shippingFee: 80.0,
        platformFee: 6.0,
        total: 386.0,
        items: const [
          OrderLineItem(
            id: 'li-2',
            title: 'Graphic Tee',
            unitPrice: 300.0,
            quantity: 1,
            lineTotal: 300.0,
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _MockAuthProvider(),
            ),
            ChangeNotifierProvider<BuyerOrdersController>(
              create: (_) => _MockBuyerOrdersController(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PaymentCheckoutBody(
                order: order1,
                groupOrders: [order1, order2],
                confirming: false,
                selectedChannel: 'gcash',
                isAbandoning: false,
                isSavingAddress: false,
                windowOpen: true,
                onSelectChannel: (_) {},
                onChangeAddress: () {},
              ),
            ),
          ),
        ),
      );

      // Section header
      expect(find.text('Your orders'), findsOneWidget);
      expect(
        find.text('2 orders from 2 shops · Pay once through PayMongo'),
        findsOneWidget,
      );

      // Order 1
      expect(find.text('Seller Alpha'), findsOneWidget);
      expect(find.text('#TL-20261008-01'), findsOneWidget);
      expect(find.text('Order 1 of 2'), findsOneWidget);
      expect(find.text('Vintage Jacket'), findsOneWidget);
      expect(find.text(formatCurrency(590.0)), findsWidgets);

      // Order 2
      expect(find.text('Seller Beta'), findsOneWidget);
      expect(find.text('#TL-20261008-02'), findsOneWidget);
      expect(find.text('Order 2 of 2'), findsOneWidget);
      expect(find.text('Graphic Tee'), findsOneWidget);
      expect(find.text(formatCurrency(386.0)), findsWidgets);

      // Combined Payment Summary
      expect(find.text('Payment summary'), findsOneWidget);
      expect(find.text('2 shops · 1 payment'), findsOneWidget);
      expect(find.text('Items subtotal (2 items, 2 shops)'), findsOneWidget);
      expect(find.text(formatCurrency(800.0)), findsOneWidget);
      expect(find.text('Shipping fee (2 shops)'), findsOneWidget);
      expect(find.text(formatCurrency(160.0)), findsOneWidget);
      expect(find.text('Platform fee (2%)'), findsNWidgets(3));
      expect(find.text(formatCurrency(16.0)), findsOneWidget);
      expect(find.text('Total payment'), findsWidgets);
      // Combined total 590 + 386 = 976
      expect(find.text(formatCurrency(976.0)), findsWidgets);
    });
  });
}
