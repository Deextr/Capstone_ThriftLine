import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/community_report_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';

class MyReportsController extends ChangeNotifier {
  MyReportsController({
    required SupabaseService supabase,
    required AuthProvider auth,
    this.reportId,
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
  final String? reportId;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  List<CommunityReportModel> _reports = [];
  CommunityReportModel? _report;
  OrderModel? _linkedOrder;
  bool _isLoading = true;
  String? _errorMessage;

  List<CommunityReportModel> get reports => _reports;
  CommunityReportModel? get report => _report;
  OrderModel? get linkedOrder => _linkedOrder;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool showSpinner = true}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _reports = [];
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
      var query = _supabase.client
          .from('reports')
          .select(
            '*, report_evidence(report_evidence_id, file_path, created_at)',
          )
          .eq('reporter_id', myId);
      if (reportId != null) {
        query = query.eq('report_id', reportId!);
      }
      final rows = await query.order('created_at', ascending: false);
      final raw = (rows as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList();

      final userIds = raw
          .map((row) => row['reported_user_id'] as String?)
          .whereType<String>()
          .toSet();
      final orderIds = raw
          .map((row) => row['order_id'] as String?)
          .whereType<String>()
          .toSet();

      final profiles = await loadPublicProfiles(_supabase, userIds);
      final orderNumbers = await _loadOrderNumbers(orderIds);

      final mapped = <CommunityReportModel>[];
      for (final row in raw) {
        final evidenceRows =
            (row['report_evidence'] as List<dynamic>? ?? const [])
                .map(
                  (item) => ReportEvidenceItem.fromSupabase(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList();
        final reportedId = row['reported_user_id'] as String?;
        final orderId = row['order_id'] as String?;
        mapped.add(
          CommunityReportModel.fromSupabase(
            row,
            reportedUser: reportedId == null ? null : profiles[reportedId],
            orderNumber: orderId == null ? null : orderNumbers[orderId],
            evidence: evidenceRows,
          ),
        );
      }

      if (reportId != null) {
        _report = mapped.isEmpty ? null : mapped.first;
        _linkedOrder = null;
        if (_report == null) {
          _errorMessage = 'Report not found.';
        } else {
          _report = await _withSignedUrls(_report!);
          _linkedOrder = await _loadLinkedOrder(_report!);
        }
        _reports = mapped;
      } else {
        _reports = mapped;
        _linkedOrder = null;
      }
    } catch (e) {
      debugPrint('MyReportsController.load error: $e');
      _errorMessage = 'Unable to load your reports.';
      _reports = [];
      _report = null;
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<OrderModel?> _loadLinkedOrder(CommunityReportModel report) async {
    final orderId = report.orderId;
    final buyerId = _auth.user?.id;
    if (orderId == null || orderId.isEmpty || buyerId == null) {
      return null;
    }
    try {
      return await fetchOrderById(_supabase, orderId, buyerId: buyerId);
    } catch (e) {
      debugPrint('MyReportsController linked order error: $e');
      return null;
    }
  }

  Future<Map<String, String>> _loadOrderNumbers(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase.client
          .from('orders')
          .select('order_id, order_number')
          .inFilter('order_id', ids.toList());
      final out = <String, String>{};
      for (final raw in rows as List<dynamic>) {
        final map = raw as Map<String, dynamic>;
        final id = map['order_id'] as String?;
        final number = map['order_number'] as String?;
        if (id != null && number != null) out[id] = number;
      }
      return out;
    } catch (e) {
      debugPrint('MyReportsController order numbers error: $e');
      return {};
    }
  }

  Future<CommunityReportModel> _withSignedUrls(
    CommunityReportModel report,
  ) async {
    if (report.evidence.isEmpty) return report;
    final signed = <ReportEvidenceItem>[];
    for (final item in report.evidence) {
      try {
        final url = await _supabase.client.storage
            .from('report-evidence')
            .createSignedUrl(item.filePath, 3600);
        signed.add(item.copyWith(signedUrl: url));
      } catch (e) {
        debugPrint('report evidence signed URL error: $e');
        signed.add(item);
      }
    }
    return report.copyWith(evidence: signed);
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    super.dispose();
  }
}
