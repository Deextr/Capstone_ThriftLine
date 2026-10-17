import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_refunds_service.dart';
import '../domain/admin_buyer_refund.dart';

class AdminBuyerRefundsController extends ChangeNotifier {
  AdminBuyerRefundsController({
    required SupabaseService supabase,
    AdminRefundsService? service,
    this.onNeedsActionCountChanged,
    AdminBuyerRefundStatusFilter initialStatus =
        AdminBuyerRefundStatusFilter.needsAction,
  }) : _service = service ?? AdminRefundsService(supabase),
       _status = initialStatus {
    load();
  }

  final AdminRefundsService _service;
  final ValueChanged<int>? onNeedsActionCountChanged;

  List<AdminBuyerRefundRow> _rows = const [];
  AdminBuyerRefundCounts _counts = const AdminBuyerRefundCounts();
  int _total = 0;
  bool _isLoading = true;
  String? _errorMessage;
  AdminBuyerRefundStatusFilter _status;
  String _search = '';
  int _page = 1;
  int _pageSize = 25;
  int _loadEpoch = 0;
  Timer? _searchDebounce;

  List<AdminBuyerRefundRow> get rows => _rows;
  AdminBuyerRefundCounts get counts => _counts;
  int get total => _total;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AdminBuyerRefundStatusFilter get status => _status;
  String get search => _search;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get hasActiveFilters =>
      _status != AdminBuyerRefundStatusFilter.needsAction || _search.isNotEmpty;

  Future<void> load() async {
    final epoch = ++_loadEpoch;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _service.list(
        status: _status,
        search: _search,
        limit: _pageSize,
        offset: (_page - 1) * _pageSize,
      );
      if (epoch != _loadEpoch) return;
      _rows = result.items;
      _total = result.total;
      _counts = result.counts;
      onNeedsActionCountChanged?.call(result.counts.needsAction);
    } catch (e) {
      if (epoch != _loadEpoch) return;
      debugPrint('AdminBuyerRefundsController.load error: $e');
      _errorMessage = 'Unable to load buyer refunds. Try again.';
    } finally {
      if (epoch == _loadEpoch) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setStatus(AdminBuyerRefundStatusFilter value) {
    if (_status == value) return;
    _status = value;
    _page = 1;
    load();
  }

  void scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => setSearch(value),
    );
  }

  void setSearch(String value) {
    final next = value.trim();
    if (next == _search) return;
    _search = next;
    _page = 1;
    load();
  }

  void setPage(int value) {
    if (value == _page || value < 1) return;
    _page = value;
    load();
  }

  void setPageSize(int value) {
    if (value == _pageSize || value < 1) return;
    _pageSize = value;
    _page = 1;
    load();
  }

  void resetFilters() {
    _status = AdminBuyerRefundStatusFilter.needsAction;
    _search = '';
    _page = 1;
    load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
