import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/admin_bidding_violations_service.dart';
import '../domain/auction_bidding_violations.dart';

class AdminBiddingViolationsController extends ChangeNotifier {
  AdminBiddingViolationsController({
    required AdminBiddingViolationsService service,
    BiddingRestrictionStatusFilter initialStatus =
        BiddingRestrictionStatusFilter.all,
  }) : _service = service,
       _statusFilter = initialStatus;

  final AdminBiddingViolationsService _service;

  bool _loading = false;
  String? _error;
  List<BiddingViolatorSummary> _summaries = const [];
  BiddingViolationsOverviewStats _stats = BiddingViolationsOverviewStats.empty;

  String _searchQuery = '';
  ViolationCountFilter _violationCountFilter = ViolationCountFilter.all;
  BiddingRestrictionStatusFilter _statusFilter;
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  bool get isLoading => _loading;
  String? get error => _error;
  BiddingViolationsOverviewStats get stats => _stats;
  String get searchQuery => _searchQuery;
  ViolationCountFilter get violationCountFilter => _violationCountFilter;
  BiddingRestrictionStatusFilter get statusFilter => _statusFilter;

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _violationCountFilter != ViolationCountFilter.all ||
      _statusFilter != BiddingRestrictionStatusFilter.all;

  List<BiddingViolatorSummary> get rows {
    final now = DateTime.now();
    var list = _summaries.where((row) {
      if (!matchesViolationCountFilter(
        row.violationCount,
        _violationCountFilter,
      )) {
        return false;
      }
      if (!matchesBiddingStatusFilter(
        row.enforcementStatusAt(now),
        _statusFilter,
      )) {
        return false;
      }
      return matchesBuyerSearch(
        query: _searchQuery,
        displayName: row.displayName,
        email: row.email,
        username: row.username,
        userId: row.userId,
      );
    }).toList();

    list.sort((a, b) {
      final aDate =
          a.latestViolationAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.latestViolationAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return list;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.loadViolators();
      _summaries = result.summaries;
      _stats = result.stats;
    } catch (e, st) {
      debugPrint('AdminBiddingViolationsController.load: $e\n$st');
      _error = 'Unable to load bidding violations.';
      _summaries = const [];
      _stats = BiddingViolationsOverviewStats.empty;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<BiddingViolationHistoryEntry>> loadHistory(String userId) {
    return _service.loadViolationHistory(userId);
  }

  void scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      setSearch(query);
    });
  }

  void setSearch(String query) {
    _searchDebounce?.cancel();
    _searchQuery = query.trim();
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void setViolationCountFilter(ViolationCountFilter filter) {
    _violationCountFilter = filter;
    notifyListeners();
  }

  void setStatusFilter(BiddingRestrictionStatusFilter filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  void resetFilters() {
    _searchQuery = '';
    _violationCountFilter = ViolationCountFilter.all;
    _statusFilter = BiddingRestrictionStatusFilter.all;
    notifyListeners();
  }
}
