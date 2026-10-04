import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/enums.dart';

import '../support/qa_reporter.dart';

void enumsUnitTests() {
  qaGroup('Enums', () {
    qaUnitTest('UserRole.fromString falls back to buyer', () {
      expect(UserRole.fromString('seller'), UserRole.seller);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('hacker'), UserRole.buyer);
    });

    qaUnitTest('ProductCategory.fromString matches name or label', () {
      expect(ProductCategory.fromString('shoes'), ProductCategory.shoes);
      expect(ProductCategory.fromString('Outerwear'), ProductCategory.outerwear);
      expect(ProductCategory.fromString('VINTAGE'), ProductCategory.vintage);
      expect(ProductCategory.fromString('xyz'), ProductCategory.tops);
    });

    qaUnitTest('ProductCondition.fromDbString maps Postgres values', () {
      expect(ProductCondition.fromDbString('new'), ProductCondition.newWithTags);
      expect(ProductCondition.fromDbString('like_new'), ProductCondition.likeNew);
      expect(ProductCondition.fromDbString('poor'), ProductCondition.poor);
      expect(ProductCondition.fromDbString('mystery'), ProductCondition.good);
    });

    qaUnitTest('SellingType.fromDbString maps listing types', () {
      expect(SellingType.fromDbString('auction'), SellingType.auction);
      expect(SellingType.fromDbString('live_session'), SellingType.liveSession);
      expect(SellingType.fromDbString('fixed_price'), SellingType.fixedPrice);
      expect(SellingType.fromDbString('other'), SellingType.fixedPrice);
    });

    qaUnitTest('orderStatusFromDb maps aliases and defaults', () {
      expect(orderStatusFromDb('paid'), OrderStatus.preparing);
      expect(orderStatusFromDb('to_ship'), OrderStatus.preparing);
      expect(orderStatusFromDb('pending'), OrderStatus.paymentPending);
      expect(orderStatusFromDb('delivered'), OrderStatus.delivered);
      expect(orderStatusFromDb(null), OrderStatus.paymentPending);
      expect(orderStatusFromDb('???'), OrderStatus.paymentPending);
    });

    qaUnitTest('orderStatusLabel returns buyer-facing copy', () {
      expect(orderStatusLabel(OrderStatus.placed), 'Awaiting payment');
      expect(orderStatusLabel(OrderStatus.preparing), 'Paid / To ship');
      expect(orderStatusLabel(OrderStatus.delivered), 'Inspecting');
      expect(orderStatusLabel(OrderStatus.cancelled), 'Cancelled');
      expect(orderStatusLabel('custom'), 'custom');
      expect(orderStatusLabel(42), 'unknown');
    });

    qaUnitTest('DeliveryStatus round-trips through its db value', () {
      for (final status in DeliveryStatus.values) {
        expect(DeliveryStatus.fromDb(status.dbValue), status);
      }
      expect(DeliveryStatus.fromDb(null), DeliveryStatus.sellerPreparing);
    });

    qaUnitTest('DeliveryStatus phase helpers', () {
      expect(DeliveryStatus.riderAssigned.isPreparing, isTrue);
      expect(DeliveryStatus.outForDelivery.isInTransit, isTrue);
      expect(DeliveryStatus.inspectionPeriod.isInspecting, isTrue);
      expect(DeliveryStatus.pickedUp.allowsRiderUpdates, isTrue);
      expect(DeliveryStatus.outForDelivery.allowsRiderUpdates, isFalse);
      expect(DeliveryStatus.completed.isInTransit, isFalse);
    });

    qaUnitTest('delivery failure/dispute reasons parse safely', () {
      expect(DeliveryFailureReason.fromDb(null), isNull);
      expect(DeliveryFailureReason.fromDb(''), isNull);
      expect(
        DeliveryFailureReason.fromDb('incorrect_address'),
        DeliveryFailureReason.incorrectAddress,
      );
      expect(
        DeliveryFailureReason.fromDb('weird'),
        DeliveryFailureReason.other,
      );
      expect(DeliveryDisputeReason.fromDb(null), DeliveryDisputeReason.other);
      expect(
        DeliveryDisputeReason.fromDb('damaged_item'),
        DeliveryDisputeReason.damagedItem,
      );
    });

    qaUnitTest('DeliveryVehicleType defaults to motorcycle', () {
      expect(DeliveryVehicleType.fromDb('van'), DeliveryVehicleType.van);
      expect(DeliveryVehicleType.fromDb('boat'), DeliveryVehicleType.motorcycle);
    });

    qaUnitTest('MessageType db value and parsing', () {
      expect(MessageType.lookingFor.dbValue, 'looking_for');
      expect(MessageType.image.dbValue, 'image');
      expect(MessageType.fromString('lookingFor'), MessageType.lookingFor);
      expect(MessageType.fromString('looking_for'), MessageType.lookingFor);
      expect(MessageType.fromString('unknown'), MessageType.text);
    });

    qaUnitTest('Notification enums parse with system fallback', () {
      expect(
        NotificationType.fromString('report_decision'),
        NotificationType.reportDecision,
      );
      expect(NotificationType.fromString('outbid'), NotificationType.outbid);
      expect(NotificationType.fromString('zzz'), NotificationType.system);
      expect(
        NotificationAudience.fromString('seller'),
        NotificationAudience.seller,
      );
      expect(
        NotificationAudience.fromString(null),
        NotificationAudience.system,
      );
    });

    qaUnitTest('DeliveryMethod fees', () {
      expect(DeliveryMethod.standard.fee, 80);
      expect(DeliveryMethod.express.fee, 150);
      expect(DeliveryMethod.meetup.fee, 0);
    });
  });
}
