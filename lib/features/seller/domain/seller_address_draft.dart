import 'davao_barangay.dart';

const int sellerShopNameMinLength = 3;
const int sellerShopNameMaxLength = 80;

const String sellerShopNameRequiredMessage = 'Shop name is required';

const String sellerShopNameTooShortMessage =
    'Shop name must be at least 3 characters';

const String sellerShopNameTooLongMessage =
    'Shop name cannot exceed 80 characters';

const int sellerShopAddressLine1MinLength = 3;

const String sellerShopAddressRequiredMessage = 'Address is required';

const String sellerShopAddressTooShortMessage =
    'Address must be at least 3 characters';

String? sellerShopNameError(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return sellerShopNameRequiredMessage;
  if (trimmed.length < sellerShopNameMinLength) {
    return sellerShopNameTooShortMessage;
  }
  if (trimmed.length > sellerShopNameMaxLength) {
    return sellerShopNameTooLongMessage;
  }
  return null;
}

String? sellerShopAddressLine1Error(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return sellerShopAddressRequiredMessage;
  if (trimmed.length < sellerShopAddressLine1MinLength) {
    return sellerShopAddressTooShortMessage;
  }
  return null;
}

/// Seller shop address collected on Become a Seller — Step 1.
class SellerAddressDraft {
  const SellerAddressDraft({
    required this.storeName,
    required this.barangay,
    required this.addressLine1,
    this.addressLine2 = '',
  });

  final String storeName;
  final DavaoBarangay? barangay;
  final String addressLine1;
  final String addressLine2;

  String get composedShopAddress {
    final line1 = addressLine1.trim();
    final line2 = addressLine2.trim();
    if (line2.isEmpty) return line1;
    return '$line1, $line2';
  }

  /// Splits [shopAddress] stored in `seller_profiles.shop_address`.
  static ({String line1, String line2}) parseStoredShopAddress(
    String? shopAddress,
  ) {
    final s = shopAddress?.trim() ?? '';
    if (s.isEmpty) return (line1: '', line2: '');
    const sep = ', ';
    final idx = s.indexOf(sep);
    if (idx < 0) return (line1: s, line2: '');
    return (line1: s.substring(0, idx), line2: s.substring(idx + sep.length));
  }

  /// Returns a user-facing error, or null when the draft can proceed.
  static String? validate({
    required String storeName,
    required DavaoBarangay? barangay,
    required List<DavaoBarangay> allowedBarangays,
    required String addressLine1,
  }) {
    final shopNameError = sellerShopNameError(storeName);
    if (shopNameError != null) return shopNameError;
    if (!DavaoBarangay.isAllowedSelection(barangay, allowedBarangays)) {
      return 'Please select a Davao City barangay.';
    }
    final addressError = sellerShopAddressLine1Error(addressLine1);
    if (addressError != null) return addressError;
    return null;
  }
}
