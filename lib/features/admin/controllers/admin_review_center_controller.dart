import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_review_service.dart';

class AdminReviewCenterController extends ChangeNotifier {
  AdminReviewCenterController({required SupabaseService supabase})
    : _service = AdminReviewService(supabase) {
    load();
  }

  final AdminReviewService _service;

  AdminReviewCounts? _counts;
  List<AdminReviewActivity> _activity = const [];
  bool _isLoading = true;
  String? _errorMessage;

  AdminReviewCounts? get counts => _counts;
  List<AdminReviewActivity> get activity => _activity;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasCounts => _counts != null;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _counts = await _service.loadQueueCounts();
    } catch (e) {
      debugPrint('AdminReviewCenterController.load error: $e');
      _counts = null;
      _activity = const [];
      _errorMessage = 'Unable to load review queues.';
      return;
    } finally {
      if (_errorMessage != null) {
        _isLoading = false;
        notifyListeners();
      }
    }

    try {
      _activity = await _service.loadRecentActivity();
    } catch (e) {
      debugPrint('AdminReviewCenterController activity error: $e');
      _activity = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
