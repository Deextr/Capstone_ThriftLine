import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_moderation_queue_service.dart';
import '../data/admin_review_rules.dart';

class AdminDisputesHubController extends ChangeNotifier {
  AdminDisputesHubController({
    required SupabaseService supabase,
    AdminModerationCategory initialCategory = AdminModerationCategory.all,
    AdminReportListFilter initialStatus = AdminReportListFilter.all,
  }) : _service = AdminModerationQueueService(supabase),
       _category = initialCategory,
       _statusFilter = initialStatus {
    load();
  }

  final AdminModerationQueueService _service;

  AdminModerationCategory _category;
  AdminReportListFilter _statusFilter;
  AdminLookingForLifecycleFilter _lfLifecycleFilter =
      AdminLookingForLifecycleFilter.all;
  AdminDateWindow? _dateWindow;
  final TextEditingController searchController = TextEditingController();

  List<AdminModerationCaseRow> _items = const [];
  int _total = 0;
  int _page = 0;
  int _pageSize = 10;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  AdminModerationCategory get category => _category;
  AdminReportListFilter get statusFilter => _statusFilter;
  AdminLookingForLifecycleFilter get lfLifecycleFilter => _lfLifecycleFilter;
  bool get isLookingForCategory =>
      _category == AdminModerationCategory.lookingFor;
  AdminDateWindow? get dateWindow => _dateWindow;
  List<AdminModerationCaseRow> get items => _items;
  int get total => _total;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get hasActiveFilters =>
      _statusFilter != AdminReportListFilter.all ||
      _lfLifecycleFilter != AdminLookingForLifecycleFilter.all ||
      _dateWindow != null ||
      searchController.text.trim().isNotEmpty;

  void scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      setSearch(value);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void setCategory(AdminModerationCategory value) {
    if (_category == value) return;
    _category = value;
    _page = 0;
    load();
  }

  void setStatusFilter(AdminReportListFilter value) {
    if (_statusFilter == value) return;
    _statusFilter = value;
    _page = 0;
    load();
  }

  void setLfLifecycleFilter(AdminLookingForLifecycleFilter value) {
    if (_lfLifecycleFilter == value) return;
    _lfLifecycleFilter = value;
    _page = 0;
    load();
  }

  void setDateWindow(AdminDateWindow? value) {
    _dateWindow = value;
    _page = 0;
    load();
  }

  void setSearch(String value) {
    searchController.text = value;
    _page = 0;
    load();
  }

  void setPage(int value) {
    if (_page == value) return;
    _page = value;
    load();
  }

  void setPageSize(int size) {
    if (_pageSize == size) return;
    _pageSize = size;
    _page = 0;
    load();
  }

  void resetFilters() {
    _category = AdminModerationCategory.all;
    _statusFilter = AdminReportListFilter.all;
    _lfLifecycleFilter = AdminLookingForLifecycleFilter.all;
    _dateWindow = null;
    searchController.clear();
    _page = 0;
    load();
  }

  void applyCategoryFromRoute(String? param) {
    final parsed = adminModerationCategoryFromParam(param);
    if (parsed == null || parsed == _category) return;
    _category = parsed;
    _page = 0;
    load();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final page = await _service.list(
        category: _category,
        statusFilter: _statusFilter,
        lfLifecycleFilter: _lfLifecycleFilter,
        page: _page,
        pageSize: _pageSize,
        search: searchController.text,
        from: _dateWindow?.from,
        toExclusive: _dateWindow?.toExclusive,
      );
      _items = page.items;
      _total = page.total;
    } catch (e) {
      debugPrint('AdminDisputesHubController.load error: $e');
      _items = const [];
      _total = 0;
      _errorMessage = 'Unable to load disputes.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
