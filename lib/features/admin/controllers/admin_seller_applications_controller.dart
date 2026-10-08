import 'dart:async';

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

  String _status = 'all'; // 'all', 'pending', 'approved', 'rejected'
  String _search = '';
  AdminDateWindow? _window;
  int _page = 0;
  int _pageSize = 10;
  int _total = 0;

  List<SellerApplication> _applications = const [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  String get status => _status;
  AdminDashboardVerificationFilter get filter => switch (_status) {
    'approved' => AdminDashboardVerificationFilter.approved,
    'rejected' => AdminDashboardVerificationFilter.rejected,
    'all' => AdminDashboardVerificationFilter.pending,
    _ => AdminDashboardVerificationFilter.pending,
  };
  String get search => _search;
  AdminDateWindow? get window => _window;
  int get page => _page;
  int get pageSize => _pageSize;
  int get total => _total;
  int get pageCount =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  List<SellerApplication> get applications => _applications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveFilters =>
      _search.trim().isNotEmpty || _status != 'all' || _window != null;

  Future<void> setFilter(AdminDashboardVerificationFilter filter) async {
    final newStatus = switch (filter) {
      AdminDashboardVerificationFilter.pending => 'pending',
      AdminDashboardVerificationFilter.approved => 'approved',
      AdminDashboardVerificationFilter.rejected => 'rejected',
    };
    await setStatus(newStatus);
  }

  Future<void> setStatus(String status) async {
    if (_status == status) return;
    _status = status;
    _page = 0;
    await load();
  }

  void scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      unawaited(setSearch(query));
    });
  }

  Future<void> setSearch(String query) async {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (_search == trimmed) return;
    _search = trimmed;
    _page = 0;
    await load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> setWindow(AdminDateWindow? window) async {
    _window = window;
    _page = 0;
    await load();
  }

  Future<void> setPage(int newPage) async {
    final clamped = newPage.clamp(0, pageCount - 1);
    if (_page == clamped && !_isLoading) return;
    _page = clamped;
    await load();
  }

  Future<void> setPageSize(int size) async {
    if (_pageSize == size) return;
    _pageSize = size;
    _page = 0;
    await load();
  }

  Future<void> resetFilters() async {
    _status = 'all';
    _search = '';
    _window = null;
    _page = 0;
    await load();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final pagedResult = await _service.listPaged(
        page: _page,
        pageSize: _pageSize,
        status: _status,
        search: _search,
        from: _window?.from,
        toExclusive: _window?.toExclusive,
      );

      _applications = pagedResult.items;
      _total = pagedResult.total;
    } catch (e) {
      debugPrint('AdminSellerApplicationsController.load error: $e');
      _applications = const [];
      _total = 0;
      _errorMessage =
          'Unable to load seller applications. Please check your connection and try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
