import '../../../core/utils/ph_phone.dart';

class SellerPayoutMethod {
  const SellerPayoutMethod({
    required this.accountName,
    required this.mobileNumber,
    this.method = 'gcash',
  });

  final String accountName;
  final String mobileNumber;
  final String method;

  factory SellerPayoutMethod.fromMap(Map<String, dynamic> map) {
    return SellerPayoutMethod(
      accountName: (map['account_name'] as String? ?? '').trim(),
      mobileNumber: (map['mobile_number'] as String? ?? '').trim(),
      method: (map['method'] as String? ?? 'gcash').trim(),
    );
  }

  bool get isComplete =>
      gcashAccountNameError(accountName) == null &&
      gcashMobileError(mobileNumber) == null;
}

String? gcashAccountNameError(String? raw) {
  final name = raw?.trim() ?? '';
  if (name.isEmpty) return 'Enter the GCash account name.';
  if (name.length < 2) return 'Account name is too short.';
  if (name.length > 80) return 'Keep the account name under 80 characters.';
  return null;
}

String? gcashMobileError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Enter a GCash number in 09XXXXXXXXX format.';
  }
  if (normalizePhMobile(raw) == null) {
    return 'Enter a GCash number in 09XXXXXXXXX format.';
  }
  return null;
}
