import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/stock_limits.dart';
import '../data/cart_shop_group.dart';
import '../data/checkout_totals.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/address_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../profile/data/address_service.dart';
import '../data/order_query.dart';

class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required SupabaseService supabase,
    required AuthProvider auth,
    required CartProvider cart,
    AddressService? addresses,
    this.buyNowProductId,
    List<String> selectedProductIds = const [],
  }) : _supabase = supabase,
       _auth = auth,
       _cart = cart,
       _addresses = addresses ?? AddressService(supabase),
       _initialSelectedIds = selectedProductIds
           .map((id) => id.trim())
           .where((id) => id.isNotEmpty)
           .toList() {
    _initSelection();
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final CartProvider _cart;
  final AddressService _addresses;
  final String? buyNowProductId;
  final List<String> _initialSelectedIds;

  List<AddressModel> _addressBook = [];
  AddressModel? _selectedAddress;
  List<OrderModel> _awaitingPayment = [];
  final Set<String> _selectedProductIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isCancellingCheckout = false;
  String? _errorMessage;

  List<AddressModel> get addressBook => _addressBook;
  AddressModel? get selectedAddress => _selectedAddress;
  List<OrderModel> get awaitingPayment => _awaitingPayment;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get isCancellingCheckout => _isCancellingCheckout;
  String? get errorMessage => _errorMessage;
  bool get hasAddress => _selectedAddress != null;
  Set<String> get selectedProductIds => Set.unmodifiable(_selectedProductIds);

  String? get scopedProductId {
    final id = buyNowProductId?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// All available fixed-price items in the cart (or scoped product if Buy Now).
  List<CartItem> get allCartItems {
    final id = scopedProductId;
    if (id != null) {
      return _cart.fixedPriceItems.where((i) => i.product.id == id).toList();
    }
    return _cart.fixedPriceItems;
  }

  /// Kept for compatibility — returns all cart items available for checkout.
  List<CartItem> get checkoutItems => allCartItems;

  List<CartShopGroup> get checkoutShops =>
      groupCartItemsByShop(selectedItems);

  /// Cart items grouped by seller ID.
  Map<String, List<CartItem>> get itemsBySeller {
    final map = <String, List<CartItem>>{};
    for (final item in allCartItems) {
      final sId = item.product.sellerId ?? 'unknown';
      map.putIfAbsent(sId, () => []).add(item);
    }
    return map;
  }

  /// Whether a specific product is checked/selected.
  bool isSelected(String productId) => _selectedProductIds.contains(productId);

  /// Currently selected seller ID, if any.
  String? get selectedSellerId {
    for (final item in allCartItems) {
      if (_selectedProductIds.contains(item.product.id)) {
        return item.product.sellerId;
      }
    }
    return null;
  }

  /// The list of items currently checked for payment.
  List<CartItem> get selectedItems =>
      allCartItems.where((i) => _selectedProductIds.contains(i.product.id)).toList();

  int get selectedCount => selectedItems.length;

  int get remainingOtherSellerCount =>
      allCartItems.length - selectedItems.length;

  double get subtotal =>
      selectedItems.fold(0.0, (sum, item) => sum + item.subtotal);

  double get shippingFee =>
      selectedItems.isEmpty ? 0 : kCheckoutShippingPerSeller;

  double get platformFee => checkoutPlatformFee(subtotal);

  double get total => checkoutTotal(
        subtotal: subtotal,
        shippingFee: shippingFee,
        platformFee: platformFee,
      );

  bool get hasUnpaidCheckouts => _awaitingPayment.isNotEmpty;

  bool get canSubmit =>
      selectedItems.isNotEmpty &&
      hasAddress &&
      !_isSubmitting &&
      !hasUnpaidCheckouts;

  /// Toggles selection of an item.
  /// If selecting an item from a different seller, switches active seller.
  void toggleItemSelection(String productId) {
    CartItem? item;
    for (final i in allCartItems) {
      if (i.product.id == productId) {
        item = i;
        break;
      }
    }
    if (item == null) return;

    if (_selectedProductIds.contains(productId)) {
      _selectedProductIds.remove(productId);
    } else {
      final currentSeller = selectedSellerId;
      if (currentSeller != null && currentSeller != item.product.sellerId) {
        // Orders are placed per seller — switch selection to this seller
        _selectedProductIds.clear();
      }
      _selectedProductIds.add(productId);
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Selects or deselects all items for a given seller.
  void toggleSellerSelection(String sellerId) {
    final sellerItems =
        allCartItems.where((i) => i.product.sellerId == sellerId).toList();
    if (sellerItems.isEmpty) return;

    final allSelected =
        sellerItems.every((i) => _selectedProductIds.contains(i.product.id));

    if (allSelected) {
      for (final i in sellerItems) {
        _selectedProductIds.remove(i.product.id);
      }
    } else {
      _selectedProductIds.clear();
      for (final i in sellerItems) {
        _selectedProductIds.add(i.product.id);
      }
    }
    _errorMessage = null;
    notifyListeners();
  }

  void _initSelection() {
    final scopedId = scopedProductId;
    if (scopedId != null) {
      _selectedProductIds.clear();
      if (allCartItems.any((i) => i.product.id == scopedId)) {
        _selectedProductIds.add(scopedId);
      }
      return;
    }

    // Retain only IDs that are still in the cart
    final availableIds = allCartItems.map((i) => i.product.id).toSet();
    _selectedProductIds.removeWhere((id) => !availableIds.contains(id));

    if (_selectedProductIds.isEmpty && _initialSelectedIds.isNotEmpty) {
      for (final id in _initialSelectedIds) {
        if (availableIds.contains(id)) _selectedProductIds.add(id);
      }
    }

    // If nothing currently selected and cart has items:
    if (_selectedProductIds.isEmpty && allCartItems.isNotEmpty) {
      final firstSeller = firstCheckoutSellerId(
        allCartItems.map((i) => i.product.sellerId),
      );
      if (firstSeller != null) {
        for (final item in allCartItems) {
          if (item.product.sellerId == firstSeller) {
            _selectedProductIds.add(item.product.id);
          }
        }
      } else {
        _selectedProductIds.add(allCartItems.first.product.id);
      }
    }
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await syncMyUnpaidCheckouts(_supabase);
      await _cart.refresh();
      await _loadAwaitingPayment();
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
      _initSelection();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadAwaitingPayment() async {
    final buyerId = _auth.user?.id;
    if (buyerId == null) {
      _awaitingPayment = [];
      return;
    }
    try {
      final orders = await fetchOrdersForBuyer(_supabase, buyerId);
      _awaitingPayment = buyerAwaitingPayment(orders);
    } catch (e) {
      debugPrint('CheckoutController awaiting payment error: $e');
      _awaitingPayment = [];
    }
  }

  void selectAddress(AddressModel address) {
    _selectedAddress = address;
    notifyListeners();
  }

  Future<void> reloadAddresses() async {
    try {
      _addressBook = await _addresses.listMine();
      _selectedAddress = _addressBook.isEmpty
          ? null
          : _addressBook.firstWhere(
              (a) => a.isDefault,
              orElse: () => _addressBook.first,
            );
      _errorMessage = null;
    } catch (e) {
      debugPrint('CheckoutController.reloadAddresses error: $e');
      _errorMessage = 'Could not load your delivery addresses.';
    }
    notifyListeners();
  }

  /// Cancels an unpaid pending checkout, restoring its items to the cart.
  Future<String?> cancelUnpaidCheckout(String orderId) async {
    if (_isCancellingCheckout) return null;
    _isCancellingCheckout = true;
    notifyListeners();
    try {
      final rpcRes = await _supabase.client.rpc(
        'abandon_unpaid_checkout',
        params: {'p_order_id': orderId},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not cancel unpaid checkout.',
        );
      }
      await _cart.refresh();
      await _loadAwaitingPayment();
      _initSelection();
      return null;
    } catch (e) {
      debugPrint('CheckoutController.cancelUnpaidCheckout error: $e');
      return 'Could not cancel unpaid checkout.';
    } finally {
      _isCancellingCheckout = false;
      notifyListeners();
    }
  }

  /// Cancels all unpaid pending checkouts, restoring all items to the cart.
  Future<String?> cancelAllUnpaidCheckouts() async {
    if (_isCancellingCheckout || _awaitingPayment.isEmpty) return null;
    _isCancellingCheckout = true;
    notifyListeners();
    try {
      final ordersToCancel = List<OrderModel>.from(_awaitingPayment);
      for (final order in ordersToCancel) {
        await _supabase.client.rpc(
          'abandon_unpaid_checkout',
          params: {'p_order_id': order.id},
        );
      }
      await _cart.refresh();
      await _loadAwaitingPayment();
      _initSelection();
      return null;
    } catch (e) {
      debugPrint('CheckoutController.cancelAllUnpaidCheckouts error: $e');
      return 'Could not cancel unpaid checkouts.';
    } finally {
      _isCancellingCheckout = false;
      notifyListeners();
    }
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

    if (selectedItems.isEmpty) {
      const error = 'Please check at least one item to check out.';
      _errorMessage = error;
      return (orderId: null, count: 0, error: error);
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _loadAwaitingPayment();
      if (_awaitingPayment.isNotEmpty) {
        const error =
            'You have an unpaid checkout. Pay or cancel it before placing a new order.';
        _errorMessage = error;
        return (orderId: null, count: 0, error: error);
      }
      await _cart.refresh();
      _initSelection();
      final currentSelected = selectedItems;
      if (currentSelected.isEmpty) {
        final error = scopedProductId != null
            ? 'This item is no longer available.'
            : 'Selected items are no longer available in your cart.';
        _errorMessage = error;
        return (orderId: null, count: 0, error: error);
      }
      for (final item in currentSelected) {
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
      final ids = currentSelected.map((item) => item.product.id).toList();
      final multiShop = groupCartItemsByShop(currentSelected).length > 1;
      if (ids.length > 1 || multiShop) {
        params['p_product_ids'] = ids;
      } else if (ids.length == 1) {
        params['p_product_id'] = ids.first;
      }
      final rpcName = (ids.length > 1 || multiShop)
          ? 'checkout_selected_cart'
          : 'checkout_cart';
      final rpcRes = await _supabase.client.rpc(rpcName, params: params);
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
      _selectedProductIds.clear();
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
