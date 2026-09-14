import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../data/report_appeal.dart';

class ReportAppealController extends ChangeNotifier {
  ReportAppealController({
    required this.reportId,
    required SupabaseService supabase,
  }) : _service = ReportAppealService(supabase) {
    load();
  }

  final String reportId;
  final ReportAppealService _service;
  final TextEditingController detailsController = TextEditingController();

  ReportAppealContext? _context;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  ReportAppealContext? get appeal => _context;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get details => detailsController.text;

  bool get canSubmit =>
      !_isSaving &&
      (_context?.canAppeal ?? false) &&
      appealDetailsError(details) == null;

  @override
  void dispose() {
    detailsController.dispose();
    super.dispose();
  }

  void setDetails(String value) {
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _context = await _service.load(reportId);
    } catch (e) {
      debugPrint('ReportAppealController.load error: $e');
      _context = null;
      _errorMessage = e is StateError
          ? e.message
          : 'Unable to load this review.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> submit() async {
    final error = appealDetailsError(details);
    if (error != null) return error;
    if (!canSubmit) return 'You cannot appeal this review.';
    if (_isSaving) return null;

    _isSaving = true;
    notifyListeners();
    try {
      final result = await _service.submit(
        reportId: reportId,
        details: details,
      );
      if (result != null) return result;
      await load();
      return null;
    } catch (e) {
      debugPrint('ReportAppealController.submit error: $e');
      return 'Could not send your appeal.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
