import 'package:flutter/foundation.dart';

import '../data/admin_audit_log_models.dart';
import '../data/admin_audit_service.dart';
import '../data/admin_dashboard_models.dart';

class AdminAuditLogsController extends ChangeNotifier {
  AdminAuditLogsController({required AdminAuditService service})
    : _service = service {
    load();
  }

  final AdminAuditService _service;

  List<AdminAuditLogRow> _rows = const [];
  AdminAuditLogRow? _selected;
  int _total = 0;
  int _page = 0;
  static const int pageSize = 25;
  bool _loading = true;
  String? _error;

  String _search = '';
  String _category = AdminAuditCategory.all;
  String _status = AdminAuditStatusFilter.all;
  AdminDateWindow? _window;

  List<AdminAuditLogRow> get rows => _rows;
  AdminAuditLogRow? get selected => _selected;
  int get total => _total;
  int get page => _page;
  int get pageCount =>
      _total <= 0 ? 1 : ((_total + pageSize - 1) ~/ pageSize);
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  String get search => _search;
  String get category => _category;
  String get status => _status;
  AdminDateWindow? get window => _window;

  bool get hasActiveFilters =>
      _search.trim().isNotEmpty ||
      _category != AdminAuditCategory.all ||
      _status != AdminAuditStatusFilter.all ||
      _window != null;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.list(
        search: _search,
        category: _category,
        status: _status,
        from: _window?.from,
        toExclusive: _window?.toExclusive,
        limit: pageSize,
        offset: _page * pageSize,
      );
      _rows = result.rows;
      _total = result.total;
      if (_selected != null &&
          !_rows.any((r) => r.logId == _selected!.logId)) {
        _selected = null;
      }
    } catch (e) {
      debugPrint('AdminAuditLogsController.load error: $e');
      _rows = const [];
      _total = 0;
      _error = 'Unable to load audit logs. Please try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(AdminAuditLogRow? row) {
    _selected = row;
    notifyListeners();
  }

  Future<void> setSearch(String value) async {
    _search = value.trim();
    _page = 0;
    await load();
  }

  Future<void> setCategory(String value) async {
    _category = value;
    _page = 0;
    await load();
  }

  Future<void> setStatus(String value) async {
    _status = value;
    _page = 0;
    await load();
  }

  Future<void> setWindow(AdminDateWindow? value) async {
    _window = value;
    _page = 0;
    await load();
  }

  Future<void> resetFilters() async {
    _search = '';
    _category = AdminAuditCategory.all;
    _status = AdminAuditStatusFilter.all;
    _window = null;
    _page = 0;
    await load();
  }

  Future<void> setPage(int page) async {
    _page = page.clamp(0, pageCount - 1);
    await load();
  }
}
