import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_verification_service.dart';

class AdminSellerApplicationsController extends ChangeNotifier {
  AdminSellerApplicationsController({required SupabaseService supabase})
    : _service = AdminVerificationService(supabase) {
    load();
  }

  final AdminVerificationService _service;

  List<SellerApplication> _applications = const [];
  bool _isLoading = true;
  String? _errorMessage;

  List<SellerApplication> get applications => _applications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _applications = await _service.listPending();
    } catch (e) {
      debugPrint('AdminSellerApplicationsController.load error: $e');
      _applications = const [];
      _errorMessage = 'Unable to load seller applications.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
