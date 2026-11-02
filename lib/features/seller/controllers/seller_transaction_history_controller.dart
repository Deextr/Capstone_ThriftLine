import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../providers/auth_provider.dart';
import '../data/seller_earnings.dart';
import '../data/seller_transaction.dart';

enum SellerTransactionHistoryMode { sales, payouts }

class SellerTransactionHistoryController extends ChangeNotifier {
  SellerTransactionHistoryController({
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;

  List<SellerTransaction> _transactions = const [];
  List<SellerPayoutRecord> _payouts = const [];
  bool _isLoading = true;
  String? _errorMessage;
  BuyerTransactionFilter _filter = BuyerTransactionFilter.all;
  BuyerTransactionSort _sort = BuyerTransactionSort.newest;
  SellerTransactionHistoryMode _mode = SellerTransactionHistoryMode.sales;

  List<SellerTransaction> get transactions => _transactions;
  List<SellerPayoutRecord> get payouts => _payouts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  BuyerTransactionFilter get filter => _filter;
  BuyerTransactionSort get sort => _sort;
  SellerTransactionHistoryMode get mode => _mode;

  bool get hasAnyTransactions => _transactions.isNotEmpty;
  bool get hasAnyPayouts => _payouts.isNotEmpty;
  bool get hasAnyHistory => hasAnyTransactions || hasAnyPayouts;

  List<SellerTransaction> get visibleTransactions => visibleSellerTransactions(
    source: _transactions,
    filter: _filter,
    sort: _sort,
  );

  int countForFilter(BuyerTransactionFilter value) {
    return sellerTransactionCountForFilter(_transactions, value);
  }

  SellerTransaction? transactionById(String paymentId) {
    for (final t in _transactions) {
      if (t.paymentId == paymentId) return t;
    }
    return null;
  }

  SellerPayoutRecord? payoutById(String payoutId) {
    for (final p in _payouts) {
      if (p.payoutId == payoutId) return p;
    }
    return null;
  }

  void setMode(SellerTransactionHistoryMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
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
      final results = await Future.wait([
        _supabase.client.rpc('list_my_seller_payment_transactions'),
        _supabase.client.rpc('seller_earnings_snapshot'),
      ]);
      final raw = results[0];
      final rows = raw is List ? raw : const [];
      final parsed = <SellerTransaction>[];
      for (final row in rows) {
        if (row is! Map) continue;
        try {
          parsed.add(
            SellerTransaction.fromJson(Map<String, dynamic>.from(row)),
          );
        } on FormatException {
          continue;
        }
      }
      parsed.sort((a, b) => b.sortDate.compareTo(a.sortDate));
      _transactions = parsed;

      final snapshot = supabaseRpcMap(results[1]);
      if (snapshot != null && snapshot['success'] == true) {
        final payoutRows = snapshot['payouts'];
        if (payoutRows is List) {
          _payouts = payoutRows
              .whereType<Map>()
              .map(
                (m) => SellerPayoutRecord.fromMap(Map<String, dynamic>.from(m)),
              )
              .toList();
        } else {
          _payouts = const [];
        }
      } else {
        _payouts = const [];
      }
    } catch (e) {
      debugPrint('list_my_seller_payment_transactions error: $e');
      _errorMessage = userFacingOrderLoadError(
        e,
        fallback: 'Unable to load transactions. Please try again.',
      );
      _payouts = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
