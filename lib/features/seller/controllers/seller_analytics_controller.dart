import 'package:flutter/foundation.dart';

import '../data/seller_analytics.dart';
import '../data/seller_analytics_period.dart';
import '../data/seller_analytics_service.dart';

class SellerAnalyticsController extends ChangeNotifier {
  SellerAnalyticsController({required SellerAnalyticsService service})
    : _service = service {
    _loadForPreset(SellerAnalyticsPreset.last7Days);
  }

  final SellerAnalyticsService _service;

  SellerAnalyticsPreset _preset = SellerAnalyticsPreset.last7Days;
  DateTime? _customStart;
  DateTime? _customEnd;
  SellerAnalyticsPeriodWindow? _window;
  SellerAnalyticsReport? _report;
  bool _isLoading = false;
  String? _errorMessage;
  String? _validationMessage;

  SellerAnalyticsPreset get preset => _preset;
  SellerAnalyticsPeriodWindow? get window => _window;
  SellerAnalyticsReport? get report => _report;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get validationMessage => _validationMessage;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;

  Future<void> selectPreset(SellerAnalyticsPreset next) async {
    if (_preset == next && next != SellerAnalyticsPreset.custom) return;
    _preset = next;
    _validationMessage = null;
    if (next != SellerAnalyticsPreset.custom) {
      await _loadForPreset(next);
    } else {
      notifyListeners();
    }
  }

  Future<void> applyCustomRange(DateTime start, DateTime end) async {
    _preset = SellerAnalyticsPreset.custom;
    _customStart = start;
    _customEnd = end;
    _validationMessage = null;
    try {
      _window = resolveSellerAnalyticsPeriod(
        preset: SellerAnalyticsPreset.custom,
        customStartLocal: start,
        customEndLocal: end,
      );
      await _fetch();
    } on SellerAnalyticsPeriodException catch (e) {
      _validationMessage = e.message;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_preset == SellerAnalyticsPreset.custom &&
        _customStart != null &&
        _customEnd != null) {
      await applyCustomRange(_customStart!, _customEnd!);
      return;
    }
    await _loadForPreset(_preset);
  }

  Future<void> _loadForPreset(SellerAnalyticsPreset preset) async {
    _validationMessage = null;
    try {
      _window = resolveSellerAnalyticsPeriod(preset: preset);
      await _fetch();
    } on SellerAnalyticsPeriodException catch (e) {
      _validationMessage = e.message;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetch() async {
    final window = _window;
    if (window == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _service.loadReport(window);
    _report = result.report;
    _errorMessage = result.error;
    _isLoading = false;
    notifyListeners();
  }
}
