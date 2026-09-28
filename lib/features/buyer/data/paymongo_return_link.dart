import '../../../core/routes/route_names.dart';

const kPaymongoAppScheme = 'thriftline';
const kPaymongoReturnHost = 'paymongo-return';

class PaymongoReturnLink {
  const PaymongoReturnLink({
    required this.orderId,
    required this.cancelled,
    this.expired = false,
  });

  final String orderId;
  final bool cancelled;
  final bool expired;

  String get appLocation => RouteNames.paymentReturnFor(
    orderId,
    cancelled: cancelled,
    expired: expired,
  );

  static PaymongoReturnLink? tryParse(Uri? uri) {
    if (uri == null) return null;
    if (!_isReturnUri(uri)) return null;
    final orderId = uri.queryParameters['order_id']?.trim() ?? '';
    if (!_isUuid(orderId)) return null;
    final status = (uri.queryParameters['status'] ?? '').trim().toLowerCase();
    return PaymongoReturnLink(
      orderId: orderId,
      cancelled: status == 'cancel' || status == 'cancelled',
      expired: status == 'expired',
    );
  }

  static bool _isReturnUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (scheme == kPaymongoAppScheme &&
        (host == kPaymongoReturnHost || path.contains(kPaymongoReturnHost))) {
      return true;
    }
    if ((scheme == 'https' || scheme == 'http') &&
        path.contains('paymongo-return')) {
      return true;
    }
    return false;
  }

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
  }
}
