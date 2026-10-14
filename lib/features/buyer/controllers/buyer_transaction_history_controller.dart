import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../providers/auth_provider.dart';
import '../data/buyer_transaction.dart';

class BuyerTransactionHistoryController extends ChangeNotifier {
  BuyerTransactionHistoryController({
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;

  List<BuyerTransaction> _transactions = const [];
  bool _isLoading = true;
  String? _errorMessage;
  BuyerTransactionFilter _filter = BuyerTransactionFilter.all;
  BuyerTransactionSort _sort = BuyerTransactionSort.newest;

  List<BuyerTransaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  BuyerTransactionFilter get filter => _filter;
  BuyerTransactionSort get sort => _sort;

  bool get hasAnyTransactions => _transactions.isNotEmpty;

  List<BuyerTransaction> get visibleTransactions => visibleBuyerTransactions(
    source: _transactions,
    filter: _filter,
    sort: _sort,
  );

  int countForFilter(BuyerTransactionFilter value) {
    if (value == BuyerTransactionFilter.all) return _transactions.length;
    return _transactions
        .where(
          (t) => switch (value) {
            BuyerTransactionFilter.all => true,
            BuyerTransactionFilter.successful =>
              t.status == BuyerTransactionStatus.successful,
            BuyerTransactionFilter.refunded =>
              t.status == BuyerTransactionStatus.refunded,
          },
        )
        .length;
  }

  void setFilter(BuyerTransactionFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setSort(BuyerTransactionSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  void resetFilters() {
    if (_filter == BuyerTransactionFilter.all &&
        _sort == BuyerTransactionSort.newest) {
      return;
    }
    _filter = BuyerTransactionFilter.all;
    _sort = BuyerTransactionSort.newest;
    notifyListeners();
  }

  Future<void> load() async {
    if (_auth.user == null) {
      _transactions = const [];
      _isLoading = false;
      _errorMessage = 'Please sign in to view your transactions.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _supabase.client.rpc('list_my_payment_transactions');
      final rows = raw is List ? raw : const [];
      final parsed = <BuyerTransaction>[];
      for (final row in rows) {
        if (row is! Map) continue;
        try {
          parsed.add(BuyerTransaction.fromJson(Map<String, dynamic>.from(row)));
        } on FormatException {
          continue;
        }
      }
      parsed.sort((a, b) => b.sortDate.compareTo(a.sortDate));
      _transactions = parsed;
    } catch (e) {
      debugPrint('list_my_payment_transactions error: $e');
      _errorMessage = userFacingOrderLoadError(
        e,
        fallback: 'Unable to load transactions. Please try again.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
