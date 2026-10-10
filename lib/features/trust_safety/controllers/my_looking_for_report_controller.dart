import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/buyer_looking_for_report_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/buyer_my_reports_query.dart';

class MyLookingForReportController extends ChangeNotifier {
  MyLookingForReportController({
    required SupabaseService supabase,
    required AuthProvider auth,
    required this.reportId,
  }) : _supabase = supabase,
       _auth = auth {
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(load());
      },
    );
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String reportId;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  BuyerLookingForReportModel? _report;
  bool _isLoading = true;
  String? _errorMessage;

  BuyerLookingForReportModel? get report => _report;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _report = null;
      _isLoading = false;
      _errorMessage = 'Please sign in.';
      notifyListeners();
      return;
    }

    if (showSpinner) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    } else {
      _errorMessage = null;
    }

    try {
      _report = await fetchBuyerLookingForReportById(_supabase, myId, reportId);
      if (_report == null) {
        _errorMessage = 'Report not found.';
      }
    } catch (e) {
      debugPrint('MyLookingForReportController.load error: $e');
      _errorMessage = 'Unable to load this report.';
      _report = null;
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    super.dispose();
  }
}
