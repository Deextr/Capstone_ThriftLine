import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/admin_account_models.dart';
import '../data/admin_account_service.dart';
import '../data/admin_portal_session.dart';

class AdminAccountsController extends ChangeNotifier {
  AdminAccountsController({required AdminAccountService service})
    : _service = service;

  final AdminAccountService _service;

  List<AdminAccountRecord> rows = const [];
  AdminAccountCounts counts = AdminAccountCounts.empty;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  String? successMessage;
  String search = '';
  String? statusFilter;
  String? roleFilter;
  int _page = 0;
  int _pageSize = 10;
  int total = 0;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  int get page => _page;
  int get pageSize => _pageSize;

  bool get hasActiveFilters =>
      search.trim().isNotEmpty || statusFilter != null || roleFilter != null;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      final page = await _service.list(
        search: search,
        status: statusFilter,
        role: roleFilter,
        limit: _pageSize,
        offset: _page * _pageSize,
      );
      rows = page.rows;
      total = page.total;
      counts = page.counts;
    } catch (e) {
      debugPrint('AdminAccountsController.load error: $e');
      AdminPortalSession.note(e);
      final text = e.toString().toLowerCase();
      errorMessage = text.contains('super admin')
          ? 'You do not have access to administrator accounts.'
          : 'Could not load administrator accounts.';
      rows = const [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
    if (search == trimmed) return;
    search = trimmed;
    _page = 0;
    await load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> setStatusFilter(String? value) async {
    statusFilter = value;
    _page = 0;
    await load();
  }

  Future<void> setRoleFilter(String? value) async {
    roleFilter = value;
    _page = 0;
    await load();
  }

  Future<void> resetFilters() async {
    search = '';
    statusFilter = null;
    roleFilter = null;
    _page = 0;
    await load();
  }

  Future<void> setPage(int page) async {
    final pageCount = total <= 0 ? 1 : ((total + _pageSize - 1) ~/ _pageSize);
    _page = page.clamp(0, pageCount - 1);
    await load();
  }

  Future<void> setPageSize(int size) async {
    if (_pageSize == size) return;
    _pageSize = size;
    _page = 0;
    await load();
  }

  Future<AdminInviteResult> create({
    required String fullName,
    required String email,
  }) {
    return _run(
      () => _service.create(fullName: fullName, email: email),
      success: 'Invitation sent.',
    );
  }

  Future<AdminInviteResult> resend(AdminAccountRecord account) {
    final id = account.invitationId;
    if (id == null) {
      return Future.value(
        const AdminInviteResult(
          ok: false,
          message: 'This invitation cannot be resent.',
        ),
      );
    }
    return _run(() => _service.resend(id), success: 'Invitation resent.');
  }

  Future<AdminInviteResult> revoke(AdminAccountRecord account) {
    final id = account.invitationId;
    if (id == null) {
      return Future.value(
        const AdminInviteResult(
          ok: false,
          message: 'This invitation cannot be revoked.',
        ),
      );
    }
    return _run(() => _service.revoke(id), success: 'Invitation revoked.');
  }

  Future<AdminInviteResult> setActive(
    AdminAccountRecord account, {
    required bool active,
  }) {
    return _run(
      () => _service.setActive(userId: account.userId, active: active),
      success: active
          ? 'Administrator activated.'
          : 'Administrator deactivated.',
    );
  }

  Future<AdminInviteResult> _run(
    Future<AdminInviteResult> Function() action, {
    required String success,
  }) async {
    isSaving = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      final result = await action();
      if (result.ok) {
        await load();
        successMessage = success;
        notifyListeners();
      } else {
        errorMessage = result.message;
        AdminPortalSession.noteCode(result.code);
        notifyListeners();
      }
      return result;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}
