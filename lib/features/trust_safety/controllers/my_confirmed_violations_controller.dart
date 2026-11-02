import 'package:flutter/foundation.dart';

import '../data/confirmed_violation_labels.dart';
import '../data/confirmed_violations_service.dart';
import '../domain/confirmed_violation.dart';

class MyConfirmedViolationsController extends ChangeNotifier {
  MyConfirmedViolationsController({required ConfirmedViolationsService service})
    : _service = service;

  final ConfirmedViolationsService _service;

  List<ConfirmedViolationSummary> _all = const [];
  bool _isLoading = false;
  String? _errorMessage;
  ConfirmedViolationCategoryFilter _categoryFilter =
      ConfirmedViolationCategoryFilter.all;
  ConfirmedViolationPenaltyFilter _penaltyFilter =
      ConfirmedViolationPenaltyFilter.all;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasAnyViolations => _all.isNotEmpty;
  int get totalCount => _all.length;
  ConfirmedViolationCategoryFilter get categoryFilter => _categoryFilter;
  ConfirmedViolationPenaltyFilter get penaltyFilter => _penaltyFilter;
  DateTime? get dateFrom => _dateFrom;
  DateTime? get dateTo => _dateTo;

  bool get filtersActive =>
      _categoryFilter != ConfirmedViolationCategoryFilter.all ||
      _penaltyFilter != ConfirmedViolationPenaltyFilter.all ||
      _dateFrom != null ||
      _dateTo != null;

  List<ConfirmedViolationSummary> get visibleItems {
    return _all.where((item) {
      if (!matchesCategoryFilter(item, _categoryFilter)) return false;
      if (!matchesPenaltyFilter(item.penaltyStatus, _penaltyFilter)) {
        return false;
      }
      if (!matchesConfirmedDateRange(item.confirmedAt, _dateFrom, _dateTo)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _all = await _service.listMine();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e is StateError
          ? e.message
          : 'Unable to load confirmed violations. Check your connection and try again.';
      if (kDebugMode) {
        debugPrint('MyConfirmedViolationsController.load: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void applyFilters({
    required ConfirmedViolationCategoryFilter category,
    required ConfirmedViolationPenaltyFilter penalty,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    _categoryFilter = category;
    _penaltyFilter = penalty;
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    notifyListeners();
  }

  void resetFilters() {
    _categoryFilter = ConfirmedViolationCategoryFilter.all;
    _penaltyFilter = ConfirmedViolationPenaltyFilter.all;
    _dateFrom = null;
    _dateTo = null;
    notifyListeners();
  }
}

class ConfirmedViolationDetailController extends ChangeNotifier {
  ConfirmedViolationDetailController({
    required ConfirmedViolationsService service,
    required this.source,
    required this.recordId,
  }) : _service = service;

  final ConfirmedViolationsService _service;
  final String source;
  final String recordId;

  ConfirmedViolationDetail? _detail;
  bool _isLoading = false;
  String? _errorMessage;

  ConfirmedViolationDetail? get detail => _detail;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _detail = await _service.loadDetail(source: source, recordId: recordId);
      _errorMessage = null;
    } catch (e) {
      _detail = null;
      _errorMessage = e is StateError
          ? e.message
          : 'Unable to load this violation. Check your connection and try again.';
      if (kDebugMode) {
        debugPrint('ConfirmedViolationDetailController.load: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
