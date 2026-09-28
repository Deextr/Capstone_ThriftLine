import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/seller_payout_method.dart';
import '../data/seller_payout_method_service.dart';

class SellerPayoutMethodController extends ChangeNotifier {
  SellerPayoutMethodController({required SupabaseService supabase})
    : _service = SellerPayoutMethodService(supabase) {
    load();
  }

  final SellerPayoutMethodService _service;

  SellerPayoutMethod? _method;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _offlineMessage;

  SellerPayoutMethod? get method => _method;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get offlineMessage => _offlineMessage;
  bool get hasGcash => _method?.isComplete == true;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    _offlineMessage = null;
    notifyListeners();
    try {
      _method = await _service.loadMine();
    } catch (e) {
      debugPrint('SellerPayoutMethodController.load: $e');
      if (isLikelyOfflineError(e)) {
        final cached = await _service.readCache();
        if (cached != null) {
          _method = cached;
          _offlineMessage =
              'No internet connection. Showing your saved GCash details.';
        } else {
          _method = null;
          _errorMessage =
              'No internet connection. Check your connection and try again.';
        }
      } else {
        _method = null;
        _errorMessage = 'Unable to load payment methods.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> save({
    required String accountName,
    required String mobileNumber,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      final error = await _service.save(
        accountName: accountName,
        mobileNumber: mobileNumber,
      );
      if (error != null) return error;
      await load();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> remove() async {
    _isSaving = true;
    notifyListeners();
    try {
      final error = await _service.deleteMine();
      if (error != null) return error;
      _method = null;
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
