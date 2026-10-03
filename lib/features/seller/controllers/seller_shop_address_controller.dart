import 'package:flutter/foundation.dart';

import '../data/davao_barangay_service.dart';
import '../data/seller_shop_address.dart';
import '../data/seller_shop_address_service.dart';
import '../domain/davao_barangay.dart';
import '../domain/seller_address_draft.dart';

class SellerShopAddressController extends ChangeNotifier {
  SellerShopAddressController({required SellerShopAddressService service})
      : _service = service {
    load();
  }

  final SellerShopAddressService _service;

  SellerShopAddress? _address;
  List<DavaoBarangay> _barangays = const [];
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _errorMessage;
  String? _validationMessage;
  bool _barangaysLoading = false;
  String? _barangayLoadError;

  SellerShopAddress? get address => _address;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  bool get isEditing => _editing;
  String? get errorMessage => _errorMessage;
  String? get validationMessage => _validationMessage;
  List<DavaoBarangay> get barangays => _barangays;
  bool get barangaysLoading => _barangaysLoading;
  String? get barangayLoadError => _barangayLoadError;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _address = await _service.loadMine();
      if (_address == null) {
        _errorMessage =
            'No seller shop profile found. Complete Become a Seller first.';
      }
    } catch (_) {
      _errorMessage = 'Could not load your shop address.';
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> startEditing() async {
    _editing = true;
    _validationMessage = null;
    notifyListeners();
    await _ensureBarangays();
  }

  void cancelEditing() {
    _editing = false;
    _validationMessage = null;
    notifyListeners();
  }

  Future<void> _ensureBarangays() async {
    if (_barangays.isNotEmpty || _barangaysLoading) return;
    _barangaysLoading = true;
    _barangayLoadError = null;
    notifyListeners();
    try {
      _barangays = await DavaoBarangayService().load();
    } catch (_) {
      _barangayLoadError = 'Could not load barangays.';
    }
    _barangaysLoading = false;
    notifyListeners();
  }

  Future<bool> save({
    required String shopName,
    required DavaoBarangay? barangay,
    required String addressLine1,
    required String addressLine2,
  }) async {
    final validationError = SellerAddressDraft.validate(
      storeName: shopName,
      barangay: barangay,
      allowedBarangays: _barangays,
      addressLine1: addressLine1,
    );
    if (validationError != null) {
      _validationMessage = validationError;
      notifyListeners();
      return false;
    }

    final draft = SellerAddressDraft(
      storeName: shopName,
      barangay: barangay,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
    );

    _saving = true;
    _validationMessage = null;
    notifyListeners();

    final error = await _service.updateMine(draft: draft);
    _saving = false;
    if (error != null) {
      _validationMessage = error;
      notifyListeners();
      return false;
    }

    _address = SellerShopAddress(
      shopName: shopName.trim(),
      barangayName: barangay!.name,
      city: DavaoBarangay.cityName,
      addressLine1: addressLine1.trim(),
      addressLine2: addressLine2.trim(),
    );
    _editing = false;
    notifyListeners();
    return true;
  }

  Future<void> retryBarangays() async {
    _barangays = const [];
    _barangaysLoading = true;
    _barangayLoadError = null;
    notifyListeners();
    try {
      _barangays = await DavaoBarangayService().load(forceRefresh: true);
    } catch (_) {
      _barangayLoadError = 'Could not load barangays.';
    }
    _barangaysLoading = false;
    notifyListeners();
  }
}
