import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/presentation/widgets/seller_order_card.dart';
import 'package:thriftline/models/order_model.dart';

void main() {
  testWidgets('shows compact seller fields without repeating status', (
    tester,
  ) async {
    final order = OrderModel.fromSupabase(
      {
        'order_id': 'order-1',
        'order_number': 'TL-10231',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'paid',
        'subtotal': 500,
        'shipping_fee': 40,
        'platform_fee': 10,
        'total_amount': 550,
        'created_at': '2026-09-13T02:00:00Z',
        'items': [
          {
            'order_item_id': 'item-1',
            'title': 'Vintage Lacoste Polo',
            'quantity': 1,
            'unit_price': 500,
            'line_total': 500,
          },
        ],
      },
      buyer: {'full_name': 'Dexter Ramos'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerOrderCard(order: order, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Order #TL-10231'), findsOneWidget);
    expect(find.text('To Ship'), findsOneWidget);
    expect(find.text('Vintage Lacoste Polo'), findsOneWidget);
    expect(find.text('Qty 1'), findsOneWidget);
    expect(find.text('Dexter R.'), findsOneWidget);
    expect(find.text('View order'), findsOneWidget);
    expect(find.text('Paid / To ship'), findsNothing);
  });
}
