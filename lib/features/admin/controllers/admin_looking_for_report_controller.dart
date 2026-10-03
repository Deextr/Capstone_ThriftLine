import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/looking_for_moderation.dart';

class AdminLookingForReportController extends ChangeNotifier {
  AdminLookingForReportController({
    required SupabaseService supabase,
    required this.reportId,
  }) : _service = LookingForModerationService(supabase) {
    load();
  }

  final LookingForModerationService _service;
  final String reportId;

  LookingForAdminReport? _report;
  List<LookingForViolationRecord> _violations = const [];
  DateTime _serverNow = DateTime.now().toUtc();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  LookingForAdminReport? get report => _report;
  List<LookingForViolationRecord> get violations => _violations;
  DateTime get serverNow => _serverNow;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _serverNow = await _service.serverNow();
      _report = await _service.getReport(reportId);
      if (_report == null) {
        _errorMessage = 'This report is no longer available.';
        _violations = const [];
      } else {
        _violations = await _service.violationsFor(_report!.reportedUserId);
      }
    } catch (e) {
      debugPrint('AdminLookingForReportController.load error: $e');
      _errorMessage = 'Unable to load this report.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> decide(String decision) async {
    final current = _report;
    if (current == null || !current.canDecide || _isSaving) {
      return 'This report has already been reviewed.';
    }
    _isSaving = true;
    notifyListeners();
    try {
      final error = await _service.decide(
        reportId: current.id,
        decision: decision,
      );
      if (error != null) return error;
      await load();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
