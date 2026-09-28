Map<String, dynamic>? supabaseRpcMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

bool supabaseRpcSuccess(dynamic value) {
  final map = supabaseRpcMap(value);
  return map != null && map['success'] == true;
}

String? supabaseRpcError(dynamic value, {String fallback = 'Request failed.'}) {
  final map = supabaseRpcMap(value);
  final error = map?['error']?.toString().trim();
  if (error != null && error.isNotEmpty) return error;
  return fallback;
}
