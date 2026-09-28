import 'davao_barangay.dart';

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

  /// Returns a user-facing error, or null when the draft can proceed.
  static String? validate({
    required String storeName,
    required DavaoBarangay? barangay,
    required List<DavaoBarangay> allowedBarangays,
    required String addressLine1,
  }) {
    if (storeName.trim().isEmpty) {
      return 'Please enter a store name.';
    }
    if (!DavaoBarangay.isAllowedSelection(barangay, allowedBarangays)) {
      return 'Please select a Davao City barangay.';
    }
    if (addressLine1.trim().isEmpty) {
      return 'Please enter Address Line 1.';
    }
    return null;
  }
}
