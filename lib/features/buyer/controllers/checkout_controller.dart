import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/stock_limits.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/address_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../profile/data/address_service.dart';

class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required SupabaseService supabase,
    required AuthProvider auth,
    required CartProvider cart,
    AddressService? addresses,
    this.buyNowProductId,
  }) : _supabase = supabase,
       _auth = auth,
       _cart = cart,
       _addresses = addresses ?? AddressService(supabase) {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final CartProvider _cart;
  final AddressService _addresses;
  final String? buyNowProductId;

  List<AddressModel> _addressBook = [];
  AddressModel? _selectedAddress;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<AddressModel> get addressBook => _addressBook;
  AddressModel? get selectedAddress => _selectedAddress;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  bool get hasAddress => _selectedAddress != null;

  String? get scopedProductId {
    final id = buyNowProductId?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  List<CartItem> get checkoutItems {
    final id = scopedProductId;
    if (id == null) return _cart.fixedPriceItems;
    return _cart.fixedPriceItems.where((i) => i.product.id == id).toList();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _cart.refresh();
      _addressBook = await _addresses.listMine();
      _selectedAddress = _addressBook.isEmpty
          ? null
          : _addressBook.firstWhere(
              (a) => a.isDefault,
              orElse: () => _addressBook.first,
            );
    } catch (e) {
      debugPrint('CheckoutController.load error: $e');
      _errorMessage = 'Could not load your delivery addresses.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectAddress(AddressModel address) {
    _selectedAddress = address;
    notifyListeners();
  }

  /// Returns the first created order id, or an error string.
  Future<({String? orderId, int count, String? error})> placeOrder() async {
    if (_auth.user?.id == null) {
      return (orderId: null, count: 0, error: 'Please sign in to check out.');
    }
    final address = _selectedAddress;
    if (address == null) {
      return (
        orderId: null,
        count: 0,
        error: 'Add a delivery address before checkout.',
      );
    }
    if (_isSubmitting) {
      return (
        orderId: null,
        count: 0,
        error: 'Checkout is already in progress.',
      );
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _cart.refresh();
      final items = checkoutItems;
      if (items.isEmpty) {
        final error = scopedProductId != null
            ? 'This item is no longer available.'
            : 'Your cart has no items that can be checked out.';
        _errorMessage = error;
        return (orderId: null, count: 0, error: error);
      }
      for (final item in items) {
        final shortage = stockShortageMessage(
          title: item.product.title,
          requested: item.quantity,
          available: item.product.maxPurchasableQuantity,
        );
        if (shortage != null) {
          _errorMessage = shortage;
          return (orderId: null, count: 0, error: shortage);
        }
      }

      final params = <String, dynamic>{'p_address_id': address.id};
      final productId = scopedProductId;
      if (productId != null) {
        params['p_product_id'] = productId;
      }
      final rpcRes = await _supabase.client.rpc(
        'checkout_cart',
        params: params,
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        final error = supabaseRpcError(
          rpcRes,
          fallback: 'Could not complete checkout.',
        );
        _errorMessage = error;
        return (orderId: null, count: 0, error: error);
      }
      final map = supabaseRpcMap(rpcRes);
      final orderId = map?['order_id'] as String?;
      final count = (map?['count'] as num?)?.toInt() ?? 1;
      if (orderId == null || orderId.isEmpty) {
        return (
          orderId: null,
          count: 0,
          error: 'Checkout succeeded but no order was returned.',
        );
      }
      await _cart.refresh();
      return (orderId: orderId, count: count, error: null);
    } catch (e) {
      debugPrint('CheckoutController.placeOrder error: $e');
      final error = _mapCheckoutError(e);
      _errorMessage = error;
      return (orderId: null, count: 0, error: error);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  String _mapCheckoutError(Object error) {
    final text = error.toString();
    if (text.contains('INSUFFICIENT_STOCK')) {
      return 'Available stock has changed. Update the quantity and try again.';
    }
    return 'Could not complete checkout. Please try again.';
  }
}
