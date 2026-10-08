import '../../../core/constants/app_constants.dart';
import '../../../core/services/shared_preferences_service.dart';

/// Survives process death / provider rebuild while PayMongo is open.
class PaymongoPendingCheckout {
  const PaymongoPendingCheckout({
    required this.orderId,
    this.checkoutGroupId,
    required this.startedAtMs,
  });

  final String orderId;
  final String? checkoutGroupId;
  final int startedAtMs;

  bool matchesOrder(String orderId) =>
      this.orderId.trim().isNotEmpty && this.orderId == orderId.trim();

  bool get isStale {
    final ageMs = DateTime.now().millisecondsSinceEpoch - startedAtMs;
    return ageMs > const Duration(hours: 2).inMilliseconds;
  }
}

class PaymongoPendingCheckoutStore {
  PaymongoPendingCheckoutStore(this._prefs);

  final SharedPreferencesService _prefs;

  static const _keyOrderId = AppConstants.keyPaymongoPendingOrderId;
  static const _keyGroupId = AppConstants.keyPaymongoPendingCheckoutGroupId;
  static const _keyStartedAt = AppConstants.keyPaymongoPendingStartedAtMs;

  Future<void> save({
    required String orderId,
    String? checkoutGroupId,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    await _prefs.setString(_keyOrderId, id);
    final group = checkoutGroupId?.trim();
    if (group != null && group.isNotEmpty) {
      await _prefs.setString(_keyGroupId, group);
    } else {
      await _prefs.remove(_keyGroupId);
    }
    await _prefs.setInt(
      _keyStartedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<PaymongoPendingCheckout?> read() async {
    final orderId = _prefs.getString(_keyOrderId)?.trim();
    if (orderId == null || orderId.isEmpty) return null;
    final startedAt = _prefs.getInt(_keyStartedAt) ?? 0;
    final group = _prefs.getString(_keyGroupId)?.trim();
    final pending = PaymongoPendingCheckout(
      orderId: orderId,
      checkoutGroupId: group != null && group.isNotEmpty ? group : null,
      startedAtMs: startedAt,
    );
    if (pending.isStale) {
      await clear();
      return null;
    }
    return pending;
  }

  Future<PaymongoPendingCheckout?> readForOrder(String orderId) async {
    final pending = await read();
    if (pending == null || !pending.matchesOrder(orderId)) return null;
    return pending;
  }

  Future<void> clear() async {
    await _prefs.remove(_keyOrderId);
    await _prefs.remove(_keyGroupId);
    await _prefs.remove(_keyStartedAt);
  }
}
