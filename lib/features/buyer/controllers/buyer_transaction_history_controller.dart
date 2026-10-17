import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../core/utils/supabase_rpc.dart';
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
    return _transactions
        .where((t) => buyerTransactionMatchesFilter(t, value))
        .length;
  }

  BuyerTransaction? transactionById(String paymentId) {
    for (final t in _transactions) {
      if (t.paymentId == paymentId) return t;
    }
    return null;
  }

  bool _isSubmittingGcash = false;
  String? _gcashError;

  bool get isSubmittingGcash => _isSubmittingGcash;
  String? get gcashError => _gcashError;

  void clearGcashError() {
    if (_gcashError == null) return;
    _gcashError = null;
    notifyListeners();
  }

  /// Sends the buyer's GCash account for a refund PayMongo could not return.
  Future<bool> submitRefundGcash({
    required BuyerTransaction transaction,
    required String accountName,
    required String mobileNumber,
  }) async {
    final escrowId = transaction.escrowId;
    if (escrowId == null || !transaction.needsGcashDetails) {
      _gcashError = 'GCash details are not needed for this refund.';
      notifyListeners();
      return false;
    }
    final nameError = validateGcashAccountName(accountName);
    final mobileError = validateGcashMobileNumber(mobileNumber);
    if (nameError != null || mobileError != null) {
      _gcashError = nameError ?? mobileError;
      notifyListeners();
      return false;
    }
    if (_isSubmittingGcash) return false;
    _isSubmittingGcash = true;
    _gcashError = null;
    notifyListeners();
    try {
      final raw = await _supabase.client.rpc(
        'submit_my_refund_gcash',
        params: {
          'p_escrow_id': escrowId,
          'p_account_name': accountName.trim(),
          'p_mobile_number': normalizePhMobileNumber(mobileNumber),
        },
      );
      final map = supabaseRpcMap(raw);
      if (map == null || map['success'] != true) {
        _gcashError = supabaseRpcError(
          map,
          fallback: 'We could not save your GCash details. Try again.',
        );
        return false;
      }
      await load();
      return true;
    } catch (e) {
      debugPrint('submit_my_refund_gcash error: $e');
      _gcashError = 'We could not save your GCash details. Try again.';
      return false;
    } finally {
      _isSubmittingGcash = false;
      notifyListeners();
    }
  }

  /// Opens the PayMongo claim link in the browser. Returns false if it failed.
  Future<bool> openRefundClaimLink(BuyerTransaction transaction) async {
    final link = safeRefundClaimLink(transaction.refundClaimLink);
    if (link == null || transaction.claimLinkExpired) return false;
    try {
      return await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('open refund claim link error: $e');
      return false;
    }
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
