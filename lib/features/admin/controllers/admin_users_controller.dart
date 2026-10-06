import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_users_service.dart';

class AdminUsersController extends ChangeNotifier {
  AdminUsersController({required SupabaseService supabase})
    : _service = AdminUsersService(supabase) {
    load();
  }

  final AdminUsersService _service;

  List<AdminUserRow> _rows = const [];
  int _total = 0;
  int _page = 0;
  static const int pageSize = 25;
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _roleFilter;
  String? _statusFilter;

  List<AdminUserRow> get rows => _rows;
  int get total => _total;
  int get page => _page;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  String get search => _search;
  String? get roleFilter => _roleFilter;
  String? get statusFilter => _statusFilter;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.list(
        page: _page,
        pageSize: pageSize,
        search: _search,
        roleFilter: _roleFilter,
        statusFilter: _statusFilter,
      );
      _rows = result.rows;
      _total = result.total;
    } catch (e) {
      debugPrint('AdminUsersController.load error: $e');
      _rows = const [];
      _error = 'Unable to load users. Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setSearch(String value) async {
    _search = value.trim();
    _page = 0;
    await load();
  }

  Future<void> setRoleFilter(String? value) async {
    _roleFilter = value;
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
}
