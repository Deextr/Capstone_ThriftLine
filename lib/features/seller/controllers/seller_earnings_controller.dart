import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/seller_earnings.dart';
import '../data/seller_earnings_service.dart';

class SellerEarningsController extends ChangeNotifier {
  SellerEarningsController({required SupabaseService supabase})
    : _service = SellerEarningsService(supabase) {
    load();
  }

  final SellerEarningsService _service;

  SellerEarningsSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isRequesting = false;
  String? _errorMessage;

  SellerEarningsSnapshot? get snapshot => _snapshot;
  bool get isLoading => _isLoading;
  bool get isRequesting => _isRequesting;
  String? get errorMessage => _errorMessage;
  bool get canRequestPayout =>
      !_isRequesting && (_snapshot?.canRequestPayout ?? false);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _snapshot = await _service.loadSnapshot();
      _errorMessage = null;
    } catch (e) {
      debugPrint('SellerEarningsController.load error: $e');
      if (!silent) _snapshot = null;
      _errorMessage = 'Unable to load earnings.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> requestPayout() async {
    final current = _snapshot;
    if (current == null || !current.canRequestPayout) {
      return 'There are no available earnings to pay out.';
    }
    if (_isRequesting) return null;

    _isRequesting = true;
    notifyListeners();
    try {
      final error = await _service.requestPayout();
      if (error != null) return error;
      await load(silent: true);
      return null;
    } finally {
      _isRequesting = false;
      notifyListeners();
    }
  }
}
