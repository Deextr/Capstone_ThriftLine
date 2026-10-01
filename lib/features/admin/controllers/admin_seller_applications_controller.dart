import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_verification_service.dart';

class AdminSellerApplicationsController extends ChangeNotifier {
  AdminSellerApplicationsController({required SupabaseService supabase})
    : _service = AdminVerificationService(supabase) {
    load();
  }

  final AdminVerificationService _service;

  AdminDashboardVerificationFilter _filter =
      AdminDashboardVerificationFilter.pending;
  List<SellerApplication> _applications = const [];
  bool _isLoading = true;
  String? _errorMessage;
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  bool _hasLoadedCounts = false;

  AdminDashboardVerificationFilter get filter => _filter;
  List<SellerApplication> get applications => _applications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pendingCount => _pendingCount;
  int get approvedCount => _approvedCount;
  int get rejectedCount => _rejectedCount;
  bool get hasLoadedCounts => _hasLoadedCounts;

  Future<void> setFilter(AdminDashboardVerificationFilter filter) async {
    if (_filter == filter) return;
    _filter = filter;
    await load();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final status = switch (_filter) {
      AdminDashboardVerificationFilter.pending => 'pending',
      AdminDashboardVerificationFilter.approved => 'approved',
      AdminDashboardVerificationFilter.rejected => 'rejected',
    };

    try {
      final (apps, counts) = await (
        _service.listByStatus(status),
        _service.countAll(),
      ).wait;
      _applications = apps;
      _pendingCount = counts.pending;
      _approvedCount = counts.approved;
      _rejectedCount = counts.rejected;
      _hasLoadedCounts = true;
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
