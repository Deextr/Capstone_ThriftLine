import '../domain/davao_barangay.dart';
import '../domain/seller_address_draft.dart';

String _composeAddressLines(String line1, String line2) {
  return SellerAddressDraft(
    storeName: '',
    barangay: null,
    addressLine1: line1,
    addressLine2: line2,
  ).composedShopAddress;
}

/// Authoritative seller shop address from `seller_profiles`.
class SellerShopAddress {
  const SellerShopAddress({
    required this.shopName,
    required this.barangayName,
    required this.city,
    required this.addressLine1,
    this.addressLine2 = '',
  });

  final String shopName;
  final String barangayName;
  final String city;
  final String addressLine1;
  final String addressLine2;

  String get composedShopAddress =>
      _composeAddressLines(addressLine1, addressLine2);

  String get displaySummary {
    final lines = <String>[
      if (addressLine1.trim().isNotEmpty) addressLine1.trim(),
      if (addressLine2.trim().isNotEmpty) addressLine2.trim(),
      if (barangayName.trim().isNotEmpty) barangayName.trim(),
      if (city.trim().isNotEmpty) city.trim(),
    ];
    return lines.join('\n');
  }

  factory SellerShopAddress.fromProfileRow(Map<String, dynamic> row) {
    final parsed = SellerAddressDraft.parseStoredShopAddress(
      row['shop_address'] as String?,
    );
    return SellerShopAddress(
      shopName: (row['shop_name'] as String?)?.trim() ?? '',
      barangayName: (row['barangay'] as String?)?.trim() ?? '',
      city: (row['city'] as String?)?.trim().isNotEmpty == true
          ? row['city'] as String
          : DavaoBarangay.cityName,
      addressLine1: parsed.line1,
      addressLine2: parsed.line2,
    );
  }

  SellerAddressDraft toDraft(DavaoBarangay? barangay) {
    return SellerAddressDraft(
      storeName: shopName,
      barangay: barangay,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
    );
  }
}
