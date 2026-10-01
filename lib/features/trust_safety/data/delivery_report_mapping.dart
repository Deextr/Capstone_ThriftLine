import '../../../models/enums.dart';

/// Maps a delivery inspection dispute reason to a community report category slug.
String deliveryDisputeReportCategory(DeliveryDisputeReason reason) {
  return switch (reason) {
    DeliveryDisputeReason.damagedItem ||
    DeliveryDisputeReason.significantlyDifferent ||
    DeliveryDisputeReason.missingItem ||
    DeliveryDisputeReason.missingQuantity ||
    DeliveryDisputeReason.emptyParcel => 'item_not_as_described',
    DeliveryDisputeReason.wrongItem => 'fake_product',
    DeliveryDisputeReason.parcelNotReceived => 'failure_to_ship',
    DeliveryDisputeReason.other => 'other',
  };
}
