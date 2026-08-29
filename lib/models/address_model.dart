class AddressModel {
  const AddressModel({
    required this.id,
    required this.userId,
    required this.recipientName,
    required this.phoneNumber,
    required this.streetAddress,
    required this.barangay,
    required this.city,
    this.postalCode,
    this.landmark,
    required this.isDefault,
  });

  final String id;
  final String userId;
  final String recipientName;
  final String phoneNumber;
  final String streetAddress;
  final String barangay;
  final String city;
  final String? postalCode;
  final String? landmark;
  final bool isDefault;

  String get formatted {
    final parts = <String>[
      streetAddress,
      barangay,
      city,
      if (postalCode != null && postalCode!.trim().isNotEmpty) postalCode!,
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(', ');
  }

  factory AddressModel.fromJson(Map<String, dynamic> json) => AddressModel(
        id: json['address_id'] as String,
        userId: json['user_id'] as String,
        recipientName: json['recipient_name'] as String? ?? '',
        phoneNumber: json['phone_number'] as String? ?? '',
        streetAddress: json['street_address'] as String? ?? '',
        barangay: json['barangay'] as String? ?? '',
        city: json['city'] as String? ?? 'Davao City',
        postalCode: json['postal_code'] as String?,
        landmark: json['landmark'] as String?,
        isDefault: json['is_default'] as bool? ?? false,
      );
}
