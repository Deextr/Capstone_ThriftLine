import 'dart:async';

import 'package:flutter/foundation.dart';

/// Notifies live [SellerListingsTab] instances to reload after listing changes.
///
/// The seller shell keeps tab state when routes such as Add Listing use
/// [GoRouter.go] instead of [GoRouter.pop], so a navigation `.then(refresh)`
/// on push is not reliable.
final class SellerListingsRefresh {
  SellerListingsRefresh._();

  static final Map<String, Set<VoidCallback>> _listeners = {};

  static void addListener(String sellerId, VoidCallback listener) {
    _listeners.putIfAbsent(sellerId, () => {}).add(listener);
  }

  static void removeListener(String sellerId, VoidCallback listener) {
    _listeners[sellerId]?.remove(listener);
    if (_listeners[sellerId]?.isEmpty ?? false) {
      _listeners.remove(sellerId);
    }
  }

  static void notify(String sellerId) {
    for (final listener in _listeners[sellerId]?.toList() ?? const []) {
      listener();
    }
  }
}
