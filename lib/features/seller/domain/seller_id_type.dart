/// Government IDs accepted for seller verification.
///
/// Digital National ID is separate from the physical National ID card.
/// Voter's ID, PhilHealth ID, and Student ID are intentionally absent and
/// must not be added as hidden, fallback, or selectable values.
enum SellerIdType {
  nationalId('national_id', 'National ID', 'Physical card'),
  digitalNationalId(
    'digital_national_id',
    'Digital National ID',
    'In the official app',
  ),
  driversLicense('drivers_license', "Driver's License", null),
  passport('passport', 'Passport', null),
  sssId('sss_id', 'SSS ID', null),
  umidId('umid_id', 'UMID', null);

  const SellerIdType(this.storageValue, this.label, this.detail);

  /// Value persisted to `user_verifications.government_id_type`.
  final String storageValue;
  final String label;

  /// Short distinction shown on the chooser. Null when the label is enough.
  final String? detail;

  /// PSA's Digital National ID is shown in the official app or national-id.gov.ph.
  /// Physical cards keep screen rejection.
  bool get presentedOnScreen => this == SellerIdType.digitalNationalId;

  /// Whether this document has a second side the seller check must photograph.
  ///
  /// Physical PhilID and the eGov Digital National ID print the issue date
  /// or the demographic block and the verification QR on the reverse.
  /// The current LTO license prints the restriction and condition legend
  /// on the back, including the DL codes on the card issued since 2021.
  /// A passport contributes its biographical photo page only.
  /// UMID keeps the photo, name, birth date, and CRN on the front; the
  /// reverse is a magnetic stripe, barcode, or agency marks.
  /// The SSS ID this check recognizes is the Social Security System card
  /// with the photo and SS number on the front. The MySSS bank card is a
  /// different document and is not a selectable type.
  bool get requiresBackCapture => switch (this) {
    SellerIdType.nationalId ||
    SellerIdType.digitalNationalId ||
    SellerIdType.driversLicense => true,
    SellerIdType.passport || SellerIdType.sssId || SellerIdType.umidId => false,
  };

  /// Stored when the applicant is not asked to pick a specific type.
  static const String unspecifiedStorageValue = 'accepted_id';

  static const List<String> prohibitedStorageValues = [
    'voters_id',
    'voter_id',
    "voter's_id",
    'philhealth_id',
    'philhealth',
    'student_id',
    'student',
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
