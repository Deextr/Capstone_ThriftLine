import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/community_report_model.dart';
import '../../../models/order_model.dart';
import '../../buyer/data/order_query.dart';
import '../data/admin_review_rules.dart';
import '../data/admin_review_service.dart';

class AdminReportsController extends ChangeNotifier {
  AdminReportsController({required SupabaseService supabase, this.reportId})
    : _supabase = supabase,
      _service = AdminReviewService(supabase) {
    load();
  }

  final SupabaseService _supabase;
  final AdminReviewService _service;
  final String? reportId;

  AdminQueueFilter _filter = AdminQueueFilter.open;
  List<CommunityReportModel> _reports = const [];
  CommunityReportModel? _report;
  OrderModel? _relatedOrder;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _decision;
  final TextEditingController responseController = TextEditingController();

  AdminQueueFilter get filter => _filter;
  List<CommunityReportModel> get reports => _reports;
  CommunityReportModel? get report => _report;
  OrderModel? get relatedOrder => _relatedOrder;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get decision => _decision;
  String get response => responseController.text;
  bool get canSubmitDecision =>
      _report != null &&
      canDecideReport(_report!.status) &&
      _decision != null &&
      adminResponseError(response) == null &&
      !_isSaving;

  @override
  void dispose() {
    responseController.dispose();
    super.dispose();
  }

  void setFilter(AdminQueueFilter value) {
    if (_filter == value) return;
    _filter = value;
    load();
  }

  void setDecision(String value) {
    _decision = value;
    notifyListeners();
  }

  void setResponse(String value) {
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (reportId != null) {
        _report = await _service.getReport(reportId!);
        _relatedOrder = null;
        if (_report == null) {
          _errorMessage = 'Report not found.';
        } else if (_report!.orderId != null && _report!.orderId!.isNotEmpty) {
          _relatedOrder = await fetchOrderById(_supabase, _report!.orderId!);
        }
        if (!canDecideReport(_report?.status ?? '')) {
          _decision = null;
        }
        final saved = _report?.adminResponse;
        if (saved != null &&
            saved.isNotEmpty &&
            responseController.text.isEmpty) {
          responseController.text = saved;
        }
      } else {
        _reports = await _service.listReports(filter: _filter);
      }
    } catch (e) {
      debugPrint('AdminReportsController.load error: $e');
      _reports = const [];
      _report = null;
      _relatedOrder = null;
      _errorMessage = reportId == null
          ? 'Unable to load community reports.'
          : 'Unable to load this report.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> submitDecision() async {
    final current = _report;
    if (current == null) return 'Report not found.';
    if (!canDecideReport(current.status)) {
      return 'This report has already been reviewed.';
    }
    final selected = _decision;
    if (selected == null || !isAllowedReportDecision(selected)) {
      return 'Choose a decision.';
    }
    final responseError = adminResponseError(response);
    if (responseError != null) return responseError;
    if (_isSaving) return null;

    _isSaving = true;
    notifyListeners();
    try {
      final error = await _service.decideReport(
        reportId: current.id,
        decision: selected,
        adminResponse: response,
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
