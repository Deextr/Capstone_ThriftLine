import 'package:flutter/foundation.dart';

import '../../features/buyer/data/paymongo_return_link.dart';

/// Holds a PayMongo app-return until routing can open the payment screen.
/// Does not mark the order paid.
class PaymongoReturnCoordinator extends ChangeNotifier {
  PaymongoReturnLink? _pending;

  PaymongoReturnLink? get pending => _pending;

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
