import '../../../models/address_model.dart';

/// Client-side guard before creating a pending order or starting PayMongo.
String? checkoutDeliveryAddressError(AddressModel? address) {
  if (address == null) {
    return 'Add a delivery address before continuing to payment.';
  }
  if (!address.isCompleteForDelivery) {
    if (!address.hasValidPhoneContact) {
      return 'Add a Philippine mobile number starting with 09 to your delivery address.';
    }
    return 'Complete your delivery address before continuing to payment.';
  }
  return null;
}
