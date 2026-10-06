import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_transactions_service.dart';

class AdminTransactionsController extends ChangeNotifier {
  AdminTransactionsController({required SupabaseService supabase})
    : _service = AdminTransactionsService(supabase) {
    load();
  }

  final AdminTransactionsService _service;

  List<AdminTransactionRow> _rows = const [];
  int _total = 0;
  int _page = 0;
  static const int pageSize = 25;
  bool _loading = true;
  String? _error;
  String? _paymentStatus;

  List<AdminTransactionRow> get rows => _rows;
  int get total => _total;
  int get page => _page;
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.list(
        page: _page,
        pageSize: pageSize,
        paymentStatus: _paymentStatus,
      );
      _rows = result.rows;
      _total = result.total;
    } catch (e) {
      debugPrint('AdminTransactionsController.load error: $e');
      _rows = const [];
      _error =
          'Unable to load transactions. Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setPaymentStatus(String? value) async {
    _paymentStatus = value;
    _page = 0;
    await load();
  }

  Future<void> setPage(int page) async {
    _page = page;
    await load();
  }
}
