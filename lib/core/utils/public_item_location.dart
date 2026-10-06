/// Privacy-safe buyer-facing location: `Barangay, Davao City` only.
String? formatPublicItemLocation({
  required bool showItemLocation,
  String? sellerBarangay,
  String sellerCity = 'Davao City',
}) {
  if (!showItemLocation) return null;
  final barangay = sellerBarangay?.trim();
  if (barangay == null || barangay.isEmpty) return null;
  final city = sellerCity.trim().isEmpty ? 'Davao City' : sellerCity.trim();
  return '$barangay, $city';
}
