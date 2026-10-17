import '../../../models/address_model.dart';

/// Client-side guard before starting PayMongo (address is set on the payment screen).
String? checkoutDeliveryAddressError(AddressModel? address) {
  if (address == null) {
    return 'Add a delivery address before paying.';
  }
  if (!address.isCompleteForDelivery) {
    if (!address.hasValidPhoneContact) {
      return 'Add a Philippine mobile number starting with 09 to your delivery address.';
    }
    return 'Complete your delivery address before paying.';
  }
  return null;
}
