import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_dashboard_service.dart';

class AdminDashboardController extends ChangeNotifier {
  AdminDashboardController({
    required SupabaseService supabase,
    SharedPreferencesService? prefs,
  }) : _service = AdminDashboardService(supabase, prefs: prefs) {
    load();
  }

  final AdminDashboardService _service;

  AdminDashboardSnapshot? _snapshot;
  List<AdminDashboardVerification> _verifications = const [];
  AdminDateWindow _window = AdminDateWindow.last7Days();
  AdminDashboardReportFilter _reportFilter = AdminDashboardReportFilter.all;
  AdminDashboardVerificationFilter _verificationFilter =
      AdminDashboardVerificationFilter.pending;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _verificationsLoading = false;
  bool _isOffline = false;
  bool _showingCachedData = false;
  String? _errorMessage;
  int _loadEpoch = 0;

  AdminDashboardSnapshot? get snapshot => _snapshot;
  AdminDashboardCounts? get counts => _snapshot?.counts;
  AdminDateWindow get window => _window;
  AdminDashboardReportFilter get reportFilter => _reportFilter;
  AdminDashboardVerificationFilter get verificationFilter =>
      _verificationFilter;
  bool get isLoading => _isLoading && _snapshot == null;
  bool get isRefreshing => _isRefreshing;
  bool get verificationsLoading => _verificationsLoading;
  bool get isOffline => _isOffline;
  bool get showingCachedData => _showingCachedData;
  String? get errorMessage => _errorMessage;
  bool get hasData => _snapshot != null;

  List<AdminDashboardVerification> get verifications => _verifications;

  List<AdminDashboardReport> get visibleReports => filterDashboardReports(
    _snapshot?.recentReports ?? const [],
    _reportFilter,
  );

  Future<void> load() async {
    final epoch = ++_loadEpoch;
    if (_snapshot == null) {
      final cached = _service.readCachedSnapshot();
      if (cached != null) {
        _snapshot = cached;
        _verifications = cached.pendingVerifications;
        _showingCachedData = true;
      }
      _isLoading = true;
    } else {
      _isRefreshing = true;
    }
    _errorMessage = null;
    _isOffline = false;
    notifyListeners();

    try {
      final window = _window;
      final snapshot = await _service.loadSnapshot(window: window);
      if (epoch != _loadEpoch) return;
      _snapshot = snapshot;
      _showingCachedData = false;
      _isOffline = false;
      _errorMessage = null;
      if (_verificationFilter == AdminDashboardVerificationFilter.pending) {
        _verifications = snapshot.pendingVerifications;
      } else {
        await _reloadVerifications();
      }
    } catch (e) {
      if (epoch != _loadEpoch) return;
      debugPrint('AdminDashboardController.load error: $e');
      _isOffline = isAdminDashboardOfflineError(e);
      if (_snapshot != null) {
        _showingCachedData = true;
        _errorMessage = _isOffline
            ? 'You appear to be offline. Showing saved dashboard numbers.'
            : 'Could not refresh the dashboard. Showing saved numbers.';
      } else {
        _errorMessage = _isOffline
            ? 'You appear to be offline. Connect and try again.'
            : 'Unable to load the dashboard.';
      }
    } finally {
      if (epoch == _loadEpoch) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> setWindow(AdminDateWindow window) async {
    _window = window;
    notifyListeners();
    await load();
  }

  void setReportFilter(AdminDashboardReportFilter filter) {
    if (_reportFilter == filter) return;
    _reportFilter = filter;
    notifyListeners();
  }

  Future<void> setVerificationFilter(
    AdminDashboardVerificationFilter filter,
  ) async {
    if (_verificationFilter == filter) return;
    _verificationFilter = filter;
    if (filter == AdminDashboardVerificationFilter.pending &&
        _snapshot != null) {
      _verifications = _snapshot!.pendingVerifications;
      notifyListeners();
      return;
    }
    await _reloadVerifications();
  }

  Future<void> _reloadVerifications() async {
    _verificationsLoading = true;
    notifyListeners();
    try {
      _verifications = await _service.listVerifications(
        filter: _verificationFilter,
      );
    } catch (e) {
      debugPrint('AdminDashboardController verifications error: $e');
      _verifications = const [];
    } finally {
      _verificationsLoading = false;
      notifyListeners();
    }
  }
}
