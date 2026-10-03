import 'package:supabase_flutter/supabase_flutter.dart';

bool isPostgrestPermissionDenied(PostgrestException error) {
  final code = error.code?.trim();
  if (code == '42501' || code == '403') return true;
  final message = error.message.toLowerCase();
  return message.contains('permission denied') ||
      message.contains('"forbidden"') ||
      message.contains('forbidden');
}

bool isLikelyNetworkError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('network is unreachable') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection timed out') ||
      text.contains('timed out');
}

/// User-safe copy for order/purchase list failures (no raw SQL in UI).
String userFacingOrderLoadError(
  Object error, {
  String fallback = 'Unable to load orders. Please try again.',
}) {
  if (error is PostgrestException && isPostgrestPermissionDenied(error)) {
    return 'We couldn\'t load your orders right now. Please try again later.';
  }
  if (isLikelyNetworkError(error)) {
    return 'Unable to load orders. Please check your connection and try again.';
  }
  return fallback;
}

bool orderSelectMightNeedShipmentFallback(PostgrestException error) {
  if (!isPostgrestPermissionDenied(error)) return false;
  final message = error.message.toLowerCase();
  return message.contains('shipments');
}
