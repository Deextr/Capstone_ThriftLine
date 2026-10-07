import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_payment_group.dart';
import 'package:thriftline/models/order_model.dart';

void main() {
  group('checkout payment group', () {
    test('group is paid only when every seller order is paid', () {
      final a = _order(id: 'a', status: 'paid', payment: 'paid');
      final b = _order(id: 'b', status: 'pending', payment: 'pending');
      expect(isCheckoutPaymentGroupPaid([a, b]), isFalse);
      expect(checkoutPaymentGroupNeedsPayment([a, b]), isTrue);

      final bPaid = _order(id: 'b', status: 'paid', payment: 'paid');
      expect(isCheckoutPaymentGroupPaid([a, bPaid]), isTrue);
      expect(checkoutPaymentGroupNeedsPayment([a, bPaid]), isFalse);
    });

    test('empty group is not paid', () {
      expect(isCheckoutPaymentGroupPaid(const []), isFalse);
      expect(checkoutPaymentGroupNeedsPayment(const []), isFalse);
    });
  });
}

OrderModel _order({
  required String id,
  required String status,
  required String payment,
}) {
  return OrderModel.fromSupabase({
    'order_id': id,
    'order_number': 'TL-$id',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-$id',
    'order_status': status,
    'subtotal': 100,
    'shipping_fee': 40,
    'platform_fee': 2,
    'total_amount': 142,
    'created_at': '2026-10-07T02:00:00Z',
    'checkout_group_id': 'group-1',
    'payments': [
      {'payment_status': payment},
    ],
  });
}
