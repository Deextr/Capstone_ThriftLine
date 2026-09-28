import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_phone.dart';
import 'package:thriftline/core/utils/rider_privacy.dart';
import 'package:thriftline/features/buyer/presentation/buyer_delivery_status.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/widgets/delivery_timeline.dart';

void main() {
  group('normalizePhMobile', () {
    test('accepts 09, +63, and 63 formats', () {
      expect(normalizePhMobile('09171234567'), '09171234567');
      expect(normalizePhMobile('+639171234567'), '09171234567');
      expect(normalizePhMobile('639171234567'), '09171234567');
      expect(normalizePhMobile('9171234567'), '09171234567');
      expect(normalizePhMobile('0917 123 4567'), '09171234567');
    });

    test('rejects invalid numbers', () {
      expect(normalizePhMobile('12345'), isNull);
      expect(normalizePhMobile('08171234567'), isNull);
      expect(isValidPhMobile(''), isFalse);
      expect(phMobileValidationError(''), isNotNull);
    });

    test(
      'formats a full number for display without changing stored digits',
      () {
        expect(formatPhMobile('09171234567'), '0917 123 4567');
        expect(formatPhMobile('+639171234567'), '0917 123 4567');
        expect(formatPhMobile('0917 123 4567'), '0917 123 4567');
        expect(normalizePhMobile('0917 123 4567'), '09171234567');
      },
    );
  });

  group('rider privacy', () {
    test('keeps seller-facing mask helpers for non-buyer surfaces', () {
      expect(maskRiderName('Juan Dela Cruz'), 'Juan C.');
      expect(maskRiderPhone('09171234567'), '09••• ••• 4567');
      expect(maskRiderPhone('09171234567', sellerView: true), '0917••••567');
    });

    test('formats inspection remaining from server timestamp', () {
      final expires = DateTime.utc(2026, 9, 13, 12, 41);
      final now = DateTime.utc(2026, 9, 12, 13);
      expect(formatInspectionRemaining(expires, now: now), '23h 41m');
      expect(
        formatInspectionRemaining(
          now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        'Inspection window ended',
      );
    });
  });

  group('order and delivery status mapping', () {
    test('keeps completed and disputed distinct', () {
      expect(orderStatusFromDb('completed'), OrderStatus.completed);
      expect(orderStatusFromDb('disputed'), OrderStatus.disputed);
      expect(orderStatusFromDb('delivered'), OrderStatus.delivered);
      expect(orderStatusFromDb('cancelled'), isNot(OrderStatus.disputed));
      expect(orderStatusLabel(OrderStatus.completed), 'Completed');
      expect(orderStatusLabel(OrderStatus.disputed), 'Disputed');
      expect(orderStatusLabel(OrderStatus.delivered), 'Inspecting');
    });

    test('parses shipment without a delivery PIN hash', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-paid',
        'order_number': 'TL-7',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'paid',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-1',
          'order_id': 'order-paid',
          'delivery_status': 'out_for_delivery',
          'delivery_method': 'freelance_rider',
          'rider_name': 'Juan Dela Cruz',
          'rider_phone': '09171234567',
          'vehicle_type': 'motorcycle',
          'out_for_delivery_at': '2026-09-12T04:00:00Z',
          'delivery_pin_hash': 'should-not-be-required',
        },
      });

      expect(order.shipment, isNotNull);
      expect(order.shipment!.deliveryStatus, DeliveryStatus.outForDelivery);
      expect(order.shipment!.pinAvailable, isTrue);
      expect(order.shipment!.buyerRiderDisplayName(), 'Juan Dela Cruz');
      expect(order.shipment!.buyerRiderPhone(), '0917 123 4567');
      expect(order.shipment!.shouldShowBuyerRiderInfo, isTrue);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isTrue);
      expect(order.shipment!.buyerRiderPhone(), isNot(contains('••')));
      expect(order.isToShip, isFalse);
      expect(order.isInTransit, isTrue);
      expect(order.isShippedTab, isTrue);
      expect(order.isTrackable, isTrue);
      expect(order.shipment!.toString(), isNot(contains('483921')));
    });

    test('paid preparing shipment stays in To Ship', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-paid',
        'order_number': 'TL-8',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'paid',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-2',
          'order_id': 'order-paid',
          'delivery_status': 'seller_preparing',
        },
      });
      expect(order.isToShip, isTrue);
      expect(order.canArrangeDelivery, isTrue);
      expect(order.isCompleted, isFalse);
      expect(order.isTrackable, isTrue);
    });

    test('inspection is not treated as completed', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-inspect',
        'order_number': 'TL-9',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'delivered',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-3',
          'order_id': 'order-inspect',
          'delivery_status': 'inspection_period',
          'delivery_verified_at': '2026-09-12T06:00:00Z',
          'inspection_expires_at': '2026-09-13T06:00:00Z',
        },
      });
      expect(order.isInspecting, isTrue);
      expect(order.isCompleted, isFalse);
      expect(order.isToShip, isFalse);
      expect(order.isShippedTab, isTrue);
      expect(order.isTrackable, isTrue);
    });

    test('pending and completed orders are not in Track Order', () {
      final pending = OrderModel.fromSupabase({
        'order_id': 'order-pending',
        'order_number': 'TL-11',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'pending',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
      });
      final completed = OrderModel.fromSupabase({
        'order_id': 'order-done',
        'order_number': 'TL-12',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'completed',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-5',
          'order_id': 'order-done',
          'delivery_status': 'completed',
        },
      });
      expect(pending.isTrackable, isFalse);
      expect(completed.isTrackable, isFalse);
      expect(completed.showsInPurchaseHistory, isTrue);
    });
  });

  group('delivery timeline', () {
    test('marks out for delivery as the current step', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-out',
        'order_number': 'TL-10',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'shipped',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-4',
          'order_id': 'order-out',
          'delivery_status': 'out_for_delivery',
          'rider_assigned_at': '2026-09-12T03:00:00Z',
          'picked_up_at': '2026-09-12T04:00:00Z',
          'out_for_delivery_at': '2026-09-12T05:00:00Z',
        },
      });
      final steps = deliveryTimelineSteps(order);
      expect(steps[0].done, isTrue);
      expect(steps[4].title, 'Out for Delivery');
      expect(steps[4].done, isTrue);
      expect(steps[4].current, isTrue);
      expect(steps[5].done, isFalse);
      expect(steps[7].done, isFalse);
    });

    test('compact buyer timeline marks out for delivery as current', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-out',
        'order_number': 'TL-10',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'shipped',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-12T02:00:00Z',
        'shipment': {
          'shipment_id': 'ship-4',
          'order_id': 'order-out',
          'delivery_status': 'out_for_delivery',
          'delivery_method': 'freelance_rider',
          'rider_assigned_at': '2026-09-12T03:00:00Z',
          'picked_up_at': '2026-09-12T04:00:00Z',
          'out_for_delivery_at': '2026-09-12T05:00:00Z',
        },
      });
      final steps = compactDeliveryTimelineSteps(order);
      expect(steps.map((step) => step.title).toList(), [
        'Payment Confirmed',
        'Preparing Order',
        'Parcel Picked Up',
        'Out for Delivery',
        'Delivered',
      ]);
      expect(steps[3].title, 'Out for Delivery');
      expect(steps[3].current, isTrue);
      expect(steps[4].current, isFalse);
      expect(steps[4].done, isFalse);
    });
  });

  group('buyer rider contact visibility', () {
    test('hides rider contact while the seller is still preparing', () {
      final order = _buyerOrder(
        deliveryStatus: 'seller_preparing',
        riderName: null,
        riderPhone: null,
      );
      expect(order.shipment!.shouldShowBuyerRiderInfo, isFalse);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isFalse);
      expect(buyerDeliveryStatus(order).title, 'Preparing Order');
      expect(buyerDeliveryStatus(order).channelLine, isNull);
    });

    test('shows the full rider number after a local rider is assigned', () {
      final order = _buyerOrder(deliveryStatus: 'rider_assigned');
      expect(order.shipment!.shouldShowBuyerRiderInfo, isTrue);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isTrue);
      expect(order.shipment!.buyerRiderDisplayName(), 'Juan Dela Cruz');
      expect(order.shipment!.buyerRiderPhone(), '0917 123 4567');
      expect(
        buyerDeliveryStatus(order).channelLine,
        'Arriving via Local Rider',
      );
    });

    test('keeps the full rider number visible while out for delivery', () {
      final order = _buyerOrder(deliveryStatus: 'out_for_delivery');
      expect(order.shipment!.isRiderContactVisibleToBuyer, isTrue);
      expect(order.shipment!.buyerRiderPhone(), isNot(contains('••')));
      expect(buyerDeliveryStatus(order).title, 'Out for Delivery');
    });

    test('hides call actions when the assigned rider has no phone', () {
      final order = _buyerOrder(
        deliveryStatus: 'out_for_delivery',
        riderPhone: null,
      );
      expect(order.shipment!.shouldShowBuyerRiderInfo, isTrue);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isFalse);
      expect(order.shipment!.buyerRiderPhone(), '');
    });

    test('hides rider contact after delivery is verified', () {
      final order = _buyerOrder(
        deliveryStatus: 'inspection_period',
        extraShipment: {
          'delivery_verified_at': '2026-09-12T06:00:00Z',
          'inspection_expires_at': '2026-09-13T06:00:00Z',
        },
      );
      expect(order.shipment!.shouldShowBuyerRiderInfo, isFalse);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isFalse);
    });

    test('does not show local rider controls for an official courier', () {
      final order = _buyerOrder(
        deliveryStatus: 'out_for_delivery',
        deliveryMethod: 'official_courier',
        riderName: null,
        riderPhone: null,
        extraOrder: {
          'courier': 'J&T Express',
          'tracking_number': '123456789012',
        },
      );
      expect(order.shipment!.isOfficialCourier, isTrue);
      expect(order.shipment!.shouldShowBuyerRiderInfo, isFalse);
      expect(order.shipment!.isRiderContactVisibleToBuyer, isFalse);
      expect(
        buyerDeliveryStatus(order).channelLine,
        'Arriving via J&T Express',
      );
    });
  });
}

OrderModel _buyerOrder({
  required String deliveryStatus,
  String deliveryMethod = 'freelance_rider',
  String? riderName = 'Juan Dela Cruz',
  String? riderPhone = '09171234567',
  Map<String, dynamic> extraShipment = const {},
  Map<String, dynamic> extraOrder = const {},
}) {
  return OrderModel.fromSupabase({
    'order_id': 'order-contact',
    'order_number': 'TL-10231',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-1',
    'order_status': 'paid',
    'subtotal': 500,
    'shipping_fee': 40,
    'platform_fee': 10,
    'total_amount': 550,
    'created_at': '2026-09-12T02:00:00Z',
    ...extraOrder,
    'shipment': {
      'shipment_id': 'ship-contact',
      'order_id': 'order-contact',
      'delivery_status': deliveryStatus,
      'delivery_method': deliveryMethod,
      if (riderName != null) 'rider_name': riderName,
      if (riderPhone != null) 'rider_phone': riderPhone,
      ...extraShipment,
    },
  });
}
