import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_users_service.dart';

class AdminUsersController extends ChangeNotifier {
  AdminUsersController({
    required SupabaseService supabase,
    AdminUsersService? service,
    bool loadOnStart = true,
  }) : _service = service ?? AdminUsersService(supabase) {
    if (loadOnStart) {
      load();
    }
  }

  final AdminUsersService _service;

  List<MarketplaceUserRow> _rows = const [];
  MarketplaceUserCounts _counts = MarketplaceUserCounts.empty;
  int _total = 0;
  int _page = 0;
  int _pageSize = 10;
  bool _loading = true;
  bool _disabling = false;
  String? _error;
  String? _notice;
  String _search = '';
  String? _accountType;
  String? _statusFilter;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  List<MarketplaceUserRow> get rows => _rows;
  MarketplaceUserCounts get counts => _counts;
  int get total => _total;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get isLoading => _loading;
  bool get isDisabling => _disabling;
  String? get errorMessage => _error;
  String? get noticeMessage => _notice;
  String get search => _search;
  String? get accountType => _accountType;
  String? get statusFilter => _statusFilter;

  bool get hasActiveFilters =>
      _search.trim().isNotEmpty ||
      _accountType != null ||
      _statusFilter != null;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.list(
        page: _page,
        pageSize: _pageSize,
        search: _search,
        accountType: _accountType,
        status: _statusFilter,
      );
      _rows = result.rows;
      _total = result.total;
      _counts = result.counts;
    } catch (e) {
      debugPrint('AdminUsersController.load error: $e');
      _rows = const [];
      _total = 0;
      _error = 'Unable to load users. Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<MarketplaceUserRow?> loadDetail(String userId) async {
    try {
      return await _service.detail(userId);
    } catch (e) {
      debugPrint('AdminUsersController.loadDetail error: $e');
      return null;
    }
  }

  /// Returns an error message when the backend rejects the disable.
  /// A null return means the account was updated and the table was refreshed.
  Future<String?> disableAccount({
    required String userId,
    required String reason,
    required String notes,
  }) async {
    if (_disabling) return 'A disable request is already in progress.';
    _disabling = true;
    _notice = null;
    notifyListeners();
    try {
      final result = await _service.disable(
        userId: userId,
        reason: reason,
        notes: notes,
      );
      if (!result.ok) {
        return result.message ??
            'Could not disable this account. Nothing was changed.';
      }
      _notice = 'Account disabled.';
      await load();
      if (_error != null) {
        return 'Account disabled, but the list could not be refreshed.';
      }
      return null;
    } finally {
      _disabling = false;
      notifyListeners();
    }
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  void scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      unawaited(setSearch(value));
    });
  }

  Future<void> setSearch(String value) async {
    _searchDebounce?.cancel();
    final trimmed = value.trim();
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

  Future<void> setAccountType(String? value) async {
    _accountType = value;
    _page = 0;
    await load();
  }

  Future<void> setStatusFilter(String? value) async {
    _statusFilter = value;
    _page = 0;
    await load();
  }

  Future<void> setPage(int page) async {
    _page = page;
    await load();
  }

  Future<void> setPageSize(int size) async {
    if (_pageSize == size) return;
    _pageSize = size;
    _page = 0;
    await load();
  }

  Future<void> resetFilters() async {
    _search = '';
    _accountType = null;
    _statusFilter = null;
    _page = 0;
    await load();
  }
}
