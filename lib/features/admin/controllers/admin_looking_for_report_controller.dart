import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_review_rules.dart';
import '../data/looking_for_moderation.dart';
import '../data/looking_for_moderation_decision_content.dart';

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
  String? _decision;
  bool _violationConfirmed = false;
  final TextEditingController responseController = TextEditingController();

  LookingForAdminReport? get report => _report;
  List<LookingForViolationRecord> get violations => _violations;
  DateTime get serverNow => _serverNow;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get decision => _decision;
  bool get violationConfirmed => _violationConfirmed;
  String? get rpcDecision =>
      lookingForDecisionToRpc(_decision) ??
      (_decision == 'resolved' ||
              _decision == 'dismissed' ||
              _decision == 'needs_more_evidence'
          ? _decision
          : null);
  String get response => responseController.text;

  bool get canSubmitDecision {
    final rpc = rpcDecision;
    return _report != null &&
        _report!.canDecide &&
        rpc != null &&
        adminResponseError(response, decision: rpc) == null &&
        !_isSaving;
  }

  @override
  void dispose() {
    responseController.dispose();
    super.dispose();
  }

  void setDecision(String? value) {
    _decision = value;
    notifyListeners();
  }

  void setViolationConfirmed(bool value) {
    _violationConfirmed = value;
    notifyListeners();
  }

  void onResponseChanged(String _) => notifyListeners();

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

  Future<String?> submitDecision() async {
    final current = _report;
    final selected = _decision;
    final rpc = rpcDecision;
    if (current == null ||
        selected == null ||
        rpc == null ||
        !current.canDecide ||
        _isSaving) {
      return 'This report has already been reviewed.';
    }
    _isSaving = true;
    notifyListeners();
    try {
      final removePost = lookingForDecisionRequiresViolation(selected);
      final error = await _service.decide(
        reportId: current.id,
        decision: rpc,
        adminResponse: response.trim(),
        violationConfirmed:
            rpc == 'resolved' && (removePost || _violationConfirmed),
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
