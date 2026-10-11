import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_orders_service.dart';
import '../domain/admin_order_management.dart';

class AdminOrdersListController extends ChangeNotifier {
  AdminOrdersListController({
    required SupabaseService supabase,
    AdminOrderCategory initialCategory = AdminOrderCategory.all,
    AdminUnifiedStatusFilter initialStatus = AdminUnifiedStatusFilter.any,
  }) : _service = AdminOrdersService(supabase),
       _category = initialCategory,
       _unifiedStatus = initialStatus {
    load();
  }

  final AdminOrdersService _service;

  List<AdminOrderRow> _rows = const [];
  int _total = 0;
  int _page = 0;
  int _pageSize = 10;
  bool _loading = true;
  String? _error;
  AdminOrderCategory _category;
  AdminUnifiedStatusFilter _unifiedStatus;
  String _search = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  AdminOrdersSort _sort = AdminOrdersSort.newest;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  List<AdminOrderRow> get rows => _rows;
  int get total => _total;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  AdminOrderCategory get category => _category;
  AdminUnifiedStatusFilter get unifiedStatus => _unifiedStatus;
  String get search => _search;
  DateTime? get dateFrom => _dateFrom;
  DateTime? get dateTo => _dateTo;
  AdminOrdersSort get sort => _sort;

  bool get hasActiveFilters =>
      _unifiedStatus != AdminUnifiedStatusFilter.any ||
      _search.trim().isNotEmpty ||
      _dateFrom != null ||
      _dateTo != null ||
      _sort != AdminOrdersSort.newest ||
      _category != AdminOrderCategory.all;

  void applyCategoryFromRoute(String? raw) {
    final next = AdminOrderCategoryX.fromQuery(raw);
    if (next == _category) return;
    _category = next;
    _page = 0;
    load();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.list(
        page: _page,
        pageSize: _pageSize,
        category: _category,
        unifiedStatus: _unifiedStatus,
        search: _search,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        sort: _sort,
      );
      _rows = result.rows;
      _total = result.total;
    } catch (e) {
      debugPrint('AdminOrdersListController.load error: $e');
      _rows = const [];
      _error = 'Unable to load orders. Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AdminOrderDetailBundle?> loadOrderDetail(String orderId) async {
    try {
      return await _service.fetchOrderDetailBundle(orderId);
    } catch (e, st) {
      debugPrint('AdminOrdersListController.loadOrderDetail error: $e\n$st');
      return null;
    }
  }

  Future<void> setCategory(AdminOrderCategory value) async {
    if (_category == value) return;
    _category = value;
    _page = 0;
    await load();
  }

  Future<void> setUnifiedStatusFilter(AdminUnifiedStatusFilter value) async {
    if (_unifiedStatus == value) return;
    _unifiedStatus = value;
    _page = 0;
    await load();
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

  Future<void> setDateRange({DateTime? from, DateTime? to}) async {
    _dateFrom = from;
    _dateTo = to;
    _page = 0;
    await load();
  }

  Future<void> setSort(AdminOrdersSort value) async {
    if (_sort == value) return;
    _sort = value;
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
    _unifiedStatus = AdminUnifiedStatusFilter.any;
    _search = '';
    _dateFrom = null;
    _dateTo = null;
    _sort = AdminOrdersSort.newest;
    _page = 0;
    await load();
  }
}
