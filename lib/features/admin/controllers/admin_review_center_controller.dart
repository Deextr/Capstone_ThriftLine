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
  bool _isLoading = true;
  String? _errorMessage;

  AdminReviewCounts? get counts => _counts;
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
      _errorMessage = 'Unable to load review queues.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
