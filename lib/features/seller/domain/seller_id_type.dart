/// Government IDs accepted for Phase 1 seller verification.
///
/// Voter's ID and PhilHealth ID are intentionally absent and must not be
/// added as hidden, fallback, or selectable values.
enum SellerIdType {
  nationalId('national_id', 'National ID'),
  driversLicense('drivers_license', "Driver's License"),
  passport('passport', 'Passport'),
  sssId('sss_id', 'SSS ID'),
  umidId('umid_id', 'UMID ID'),
  studentId('student_id', 'Student ID');

  const SellerIdType(this.storageValue, this.label);

  /// Value persisted to `user_verifications.government_id_type`.
  final String storageValue;
  final String label;

  static const List<String> prohibitedStorageValues = [
    'voters_id',
    'voter_id',
    "voter's_id",
    'philhealth_id',
    'philhealth',
  ];

  static SellerIdType? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (prohibitedStorageValues.contains(normalized)) return null;
    for (final type in SellerIdType.values) {
      if (type.storageValue == normalized) return type;
    }
    return null;
  }

  static SellerIdType parseOrThrow(String? raw) {
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw FormatException('Unsupported ID type.');
    }
    return parsed;
  }
}
