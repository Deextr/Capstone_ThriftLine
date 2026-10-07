import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_dashboard_service.dart';

class AdminAnalyticsComparison {
  const AdminAnalyticsComparison({required this.current, this.previous});

  final AdminDashboardSnapshot current;
  final AdminDashboardSnapshot? previous;

  double? percentChange(num? currentValue, num? previousValue) {
    if (previousValue == null) return null;
    if (previousValue == 0) {
      if (currentValue == null || currentValue == 0) return 0;
      return null;
    }
    if (currentValue == null) return null;
    return ((currentValue - previousValue) / previousValue) * 100;
  }
}

class AdminAnalyticsController extends ChangeNotifier {
  AdminAnalyticsController({required SupabaseService supabase})
    : _service = AdminDashboardService(supabase) {
    load();
  }

  final AdminDashboardService _service;

  AdminDateWindow _window = AdminDateWindow.last30Days();
  AdminAnalyticsComparison? _comparison;
  bool _isLoading = true;
  bool _comparePrevious = true;
  String? _errorMessage;

  AdminDateWindow get window => _window;
  AdminDashboardSnapshot? get snapshot => _comparison?.current;
  AdminDashboardSnapshot? get previousSnapshot => _comparison?.previous;
  bool get isLoading => _isLoading;
  bool get comparePrevious => _comparePrevious;
  String? get errorMessage => _errorMessage;

  AdminAnalyticsComparison? get comparison => _comparison;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final current = await _service.loadSnapshot(window: _window);
      AdminDashboardSnapshot? previous;
      if (_comparePrevious) {
        final prevWindow = _previousWindow(_window);
        if (prevWindow != null) {
          previous = await _service.loadSnapshot(window: prevWindow);
        }
      }
      _comparison = AdminAnalyticsComparison(
        current: current,
        previous: previous,
      );
    } catch (e) {
      debugPrint('AdminAnalyticsController.load error: $e');
      _comparison = null;
      _errorMessage = isAdminDashboardOfflineError(e)
          ? 'You appear to be offline. Connect and try again.'
          : 'Unable to load analytical reports.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setWindow(AdminDateWindow window) {
    if (_window.from == window.from &&
        _window.toExclusive == window.toExclusive &&
        _window.preset == window.preset) {
      return;
    }
    _window = window;
    load();
  }

  void setComparePrevious(bool value) {
    if (_comparePrevious == value) return;
    _comparePrevious = value;
    load();
  }

  AdminDateWindow? _previousWindow(AdminDateWindow current) {
    final span = current.toExclusive.difference(current.from);
    if (span.inMilliseconds <= 0) return null;
    return AdminDateWindow(
      preset: AdminDatePreset.custom,
      from: current.from.subtract(span),
      toExclusive: current.from,
    );
  }
}
