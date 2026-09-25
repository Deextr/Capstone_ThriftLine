import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/return_shipment.dart';

void main() {
  group('return status copy', () {
    test('uses human labels', () {
      expect(returnStatusLabel('waiting_for_rider'), 'Waiting for rider');
      expect(returnStatusLabel('rider_assigned'), 'Rider assigned');
      expect(returnStatusLabel('picked_up'), 'Picked up');
      expect(returnStatusLabel('returned'), 'Returned');
      expect(returnStatusLabel('not_required'), 'No return needed');
      expect(returnStatusLabel('waiting_for_rider'), isNot(contains('_')));
    });

    test('progress stays on the return steps', () {
      expect(returnProgressIndex('waiting_for_rider'), 1);
      expect(returnProgressIndex('rider_assigned'), 2);
      expect(returnProgressIndex('picked_up'), 3);
      expect(returnProgressIndex('returned'), 4);
      expect(kReturnProgressSteps.first, 'Refund approved');
    });
  });

  group('return does not reopen a failed checkout', () {
    test('a refunded cancelled order stays visible for the return', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-refunded',
        'order_number': 'TL-9',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'cancelled',
        'order_type': 'fixed_price',
        'payments': [
          {'payment_status': 'refunded'},
        ],
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 12,
        'total_amount': 592,
        'created_at': '2026-09-24T02:00:00Z',
        'item_return': {
          'return_id': 'ret-1',
          'dispute_id': 'disp-1',
          'order_id': 'order-refunded',
          'return_required': true,
          'status': 'waiting_for_rider',
        },
      });
      expect(order.isRefundedSale, isTrue);
      expect(order.isFailedCheckout, isFalse);
      expect(order.isTrackable, isTrue);
      expect(order.itemReturn?.needsRider, isTrue);
      expect(order.itemReturn?.canHandOff, isFalse);
    });

    test('an unpaid cancellation is still not a sale', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-voided',
        'order_number': 'TL-3',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'cancelled',
        'order_type': 'fixed_price',
        'subtotal': 1000,
        'shipping_fee': 80,
        'platform_fee': 20,
        'total_amount': 1100,
        'created_at': '2026-09-12T02:00:00Z',
      });
      expect(order.isFailedCheckout, isTrue);
      expect(order.isTrackable, isFalse);
    });

    test('handoff is only allowed after a rider is assigned', () {
      final waiting = ReturnShipment.fromSupabase({
        'return_id': 'r1',
        'return_required': true,
        'status': 'waiting_for_rider',
      });
      final assigned = ReturnShipment.fromSupabase({
        'return_id': 'r1',
        'return_required': true,
        'status': 'rider_assigned',
      });
      final pickedUp = ReturnShipment.fromSupabase({
        'return_id': 'r1',
        'return_required': true,
        'status': 'picked_up',
      });
      expect(waiting.canHandOff, isFalse);
      expect(waiting.canConfirmReceived, isFalse);
      expect(assigned.canHandOff, isTrue);
      expect(assigned.canConfirmReceived, isFalse);
      expect(pickedUp.canHandOff, isFalse);
      expect(pickedUp.canConfirmReceived, isTrue);
      expect(pickedUp.isOpen, isTrue);
    });
  });
}
