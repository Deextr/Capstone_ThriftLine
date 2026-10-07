import 'package:flutter/foundation.dart';

import '../../features/buyer/data/paymongo_pending_checkout_store.dart';
import '../../features/buyer/data/paymongo_return_link.dart';

/// Holds a PayMongo app-return until routing can open the payment screen.
/// Does not mark the order paid.
class PaymongoReturnCoordinator extends ChangeNotifier {
  PaymongoReturnCoordinator({PaymongoPendingCheckoutStore? pendingStore})
    : _pendingStore = pendingStore;

  final PaymongoPendingCheckoutStore? _pendingStore;

  PaymongoReturnLink? _pending;
  String? _checkoutOrderId;
  String? _checkoutGroupId;

  PaymongoReturnLink? get pending => _pending;

  /// Set when the buyer opens PayMongo hosted checkout (survives route rebuilds).
  String? get checkoutOrderId => _checkoutOrderId;

  String? get checkoutGroupId => _checkoutGroupId;

  /// Restore durable pending checkout after process death (call once at startup).
  Future<void> restorePersistedCheckout() async {
    final store = _pendingStore;
    if (store == null) return;
    final saved = await store.read();
    if (saved == null) return;
    _checkoutOrderId = saved.orderId;
    _checkoutGroupId = saved.checkoutGroupId;
    notifyListeners();
  }

  void markCheckoutOpened(String orderId, {String? checkoutGroupId}) {
    if (orderId.isEmpty) return;
    _checkoutOrderId = orderId;
    final group = checkoutGroupId?.trim();
    _checkoutGroupId = (group != null && group.isNotEmpty) ? group : null;
    notifyListeners();
    final store = _pendingStore;
    if (store != null) {
      store.save(orderId: orderId, checkoutGroupId: _checkoutGroupId);
    }
  }

  bool isAwaitingCheckout(String orderId) =>
      _checkoutOrderId != null && _checkoutOrderId == orderId;

  void clearCheckoutOpened() {
    if (_checkoutOrderId == null && _checkoutGroupId == null) return;
    _checkoutOrderId = null;
    _checkoutGroupId = null;
    notifyListeners();
    _pendingStore?.clear();
  }

  void accept(Uri uri) {
    final parsed = PaymongoReturnLink.tryParse(uri);
    if (parsed == null) return;
    _pending = parsed;
    // Deep link proves a return for this order even if in-memory flags were lost.
    if (_checkoutOrderId == null || _checkoutOrderId != parsed.orderId) {
      _checkoutOrderId = parsed.orderId;
    }
    notifyListeners();
  }

  String? peekLocation() => _pending?.appLocation;

  void clear() {
    if (_pending == null) return;
    _pending = null;
  }
}
