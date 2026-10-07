import 'package:flutter/foundation.dart';

import '../../features/buyer/data/paymongo_return_link.dart';

/// Holds a PayMongo app-return until routing can open the payment screen.
/// Does not mark the order paid.
class PaymongoReturnCoordinator extends ChangeNotifier {
  PaymongoReturnLink? _pending;
  String? _checkoutOrderId;

  PaymongoReturnLink? get pending => _pending;

  /// Set when the buyer opens PayMongo hosted checkout (survives route rebuilds).
  String? get checkoutOrderId => _checkoutOrderId;

  void markCheckoutOpened(String orderId) {
    if (orderId.isEmpty) return;
    _checkoutOrderId = orderId;
    notifyListeners();
  }

  bool isAwaitingCheckout(String orderId) =>
      _checkoutOrderId != null && _checkoutOrderId == orderId;

  void clearCheckoutOpened() {
    if (_checkoutOrderId == null) return;
    _checkoutOrderId = null;
    notifyListeners();
  }

  void accept(Uri uri) {
    final parsed = PaymongoReturnLink.tryParse(uri);
    if (parsed == null) return;
    _pending = parsed;
    notifyListeners();
  }

  String? peekLocation() => _pending?.appLocation;

  void clear() {
    if (_pending == null) return;
    _pending = null;
  }
}
