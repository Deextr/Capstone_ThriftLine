import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_dashboard_service.dart';
import '../data/admin_refunds_service.dart';
import '../data/admin_seller_payouts_service.dart';
import '../data/admin_marketplace_dashboard.dart';
import '../domain/admin_dashboard_period.dart';

class AdminDashboardController extends ChangeNotifier {
  AdminDashboardController({
    required SupabaseService supabase,
    SharedPreferencesService? prefs,
  }) : _service = AdminDashboardService(supabase, prefs: prefs),
       _payouts = AdminSellerPayoutsService(supabase),
       _refunds = AdminRefundsService(supabase) {
    load();
  }

  final AdminDashboardService _service;
  final AdminSellerPayoutsService _payouts;
  final AdminRefundsService _refunds;

  AdminMarketplaceSnapshot? _snapshot;
  AdminDashboardPeriod _period = AdminDashboardPeriod.today();
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isOffline = false;
  bool _showingCachedData = false;
  String? _errorMessage;
  int _loadEpoch = 0;

  AdminMarketplaceSnapshot? get snapshot => _snapshot;
  AdminDashboardPeriod get period => _period;
  bool get isLoading => _isLoading && _snapshot == null;
  bool get isRefreshing => _isRefreshing;
  bool get isOffline => _isOffline;
  bool get showingCachedData => _showingCachedData;
  String? get errorMessage => _errorMessage;
  bool get hasData => _snapshot != null;

  int get pendingVerificationCount =>
      _snapshot?.attention.pendingVerifications ?? 0;

  int get openDisputeCount => _snapshot?.attention.openDisputes ?? 0;

  int _pendingPayoutCount = 0;
  int _pendingBuyerRefundCount = 0;

  /// Seller payout requests still waiting for a manual GCash transfer.
  int get pendingPayoutCount => _pendingPayoutCount;

  /// Buyer refunds waiting for manual GCash or other admin follow-up.
  int get pendingBuyerRefundCount => _pendingBuyerRefundCount;

  void setPendingPayoutCount(int value) {
    if (_pendingPayoutCount == value) return;
    _pendingPayoutCount = value;
    notifyListeners();
  }

  void setPendingBuyerRefundCount(int value) {
    if (_pendingBuyerRefundCount == value) return;
    _pendingBuyerRefundCount = value;
    notifyListeners();
  }

  Future<void> _loadPendingPayoutCount() async {
    try {
      setPendingPayoutCount(await _payouts.waitingCount());
    } catch (e) {
      debugPrint('AdminDashboardController payout count error: $e');
    }
  }

  Future<void> _loadPendingBuyerRefundCount() async {
    try {
      setPendingBuyerRefundCount(await _refunds.needsActionCount());
    } catch (e) {
      debugPrint('AdminDashboardController buyer refund count error: $e');
    }
  }

  Future<void> load() async {
    unawaited(_loadPendingPayoutCount());
    unawaited(_loadPendingBuyerRefundCount());
    final epoch = ++_loadEpoch;
    if (_snapshot == null) {
      final cached = _service.readCachedMarketplace();
      if (cached != null) {
        _snapshot = cached;
        _showingCachedData = true;
      }
      _isLoading = true;
    } else {
      _isRefreshing = true;
    }
    _errorMessage = null;
    _isOffline = false;
    notifyListeners();

    try {
      final period = _period;
      final snapshot = await _service.loadMarketplace(period: period);
      if (epoch != _loadEpoch) return;
      _snapshot = snapshot;
      _showingCachedData = false;
      _isOffline = false;
      _errorMessage = null;
    } catch (e) {
      if (epoch != _loadEpoch) return;
      debugPrint('AdminDashboardController.load error: $e');
      _isOffline = isAdminDashboardOfflineError(e);
      if (_snapshot != null) {
        _showingCachedData = true;
        _errorMessage = _isOffline
            ? 'You appear to be offline. Showing saved dashboard numbers.'
            : 'Could not refresh the dashboard. Showing saved numbers.';
      } else {
        _errorMessage = _isOffline
            ? 'You appear to be offline. Connect and try again.'
            : 'Unable to load the dashboard.';
      }
    } finally {
      if (epoch == _loadEpoch) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> setPeriod(AdminDashboardPeriod period) async {
    _period = period;
    notifyListeners();
    await load();
  }
}
