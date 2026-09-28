import '../../seller/domain/davao_barangay.dart';

/// Buyer delivery addresses are Davao City only, matching Become a Seller.
String buyerAddressCity([String? _]) => DavaoBarangay.cityName;

/// Returns a snackbar message when the Add/Edit Address form is incomplete.
String? buyerAddressFormError({
  required String recipientName,
  required String phoneNumber,
  required String streetAddress,
  required DavaoBarangay? barangay,
  required List<DavaoBarangay> allowedBarangays,
}) {
  if (recipientName.trim().isEmpty ||
      phoneNumber.trim().isEmpty ||
      streetAddress.trim().isEmpty) {
    return 'Name, phone, and street are required.';
  }
  if (!DavaoBarangay.isAllowedSelection(barangay, allowedBarangays)) {
    return 'Please select a Davao City barangay.';
  }
  return null;
}
