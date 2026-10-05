/// Normalizes [report_status_enum] values from Supabase into slug strings.
String reportStatusFromDb(Object? value) {
  if (value == null) return 'under_review';
  final raw = value.toString().trim();
  if (raw.isEmpty) return 'under_review';
  return raw.toLowerCase();
}
