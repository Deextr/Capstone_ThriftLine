import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/enums.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/delivery_report_mapping.dart';
import '../data/report_evidence_upload.dart';
import '../data/report_reasons.dart';
import 'report_user_controller.dart';

class OrderDeliveryReportController extends ChangeNotifier {
  OrderDeliveryReportController({
    required SupabaseService supabase,
    required AuthProvider auth,
    required this.orderId,
    ImagePicker? picker,
  }) : _supabase = supabase,
       _auth = auth,
       _picker = picker ?? ImagePicker() {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String orderId;
  final ImagePicker _picker;

  OrderModel? _order;
  DeliveryDisputeReason? _reason;
  String _details = '';
  final List<ReportEvidenceDraft> _evidence = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _evidenceError;

  OrderModel? get order => _order;
  DeliveryDisputeReason? get reason => _reason;
  String get details => _details;
  List<ReportEvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get evidenceError => _evidenceError;

  bool get canSubmit {
    if (_isSubmitting || _order == null || _reason == null) return false;
    if (reportDetailsError(_details) != null) return false;
    if (_evidence.length < kReportEvidenceMinCount) return false;
    return true;
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final buyerId = _auth.user?.id;
      if (buyerId == null) {
        _errorMessage = 'Please sign in.';
        return;
      }
      final orders = await fetchOrdersForBuyer(_supabase, buyerId);
      OrderModel? found;
      for (final o in orders) {
        if (o.id == orderId) {
          found = o;
          break;
        }
      }
      _order = found;
      if (_order == null) {
        _errorMessage = 'Order not found.';
      }
    } catch (e) {
      debugPrint('OrderDeliveryReportController.load error: $e');
      _errorMessage = 'Unable to load this order.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectReason(DeliveryDisputeReason reason) {
    _reason = reason;
    notifyListeners();
  }

  void setDetails(String value) {
    _details = value;
    notifyListeners();
  }

  Future<String?> addEvidenceFromGallery() => _addEvidence(ImageSource.gallery);

  Future<String?> addEvidenceFromCamera() => _addEvidence(ImageSource.camera);

  Future<String?> _addEvidence(ImageSource source) async {
    _evidenceError = null;
    if (_evidence.length >= kReportEvidenceMaxCount) {
      return 'You can attach up to $kReportEvidenceMaxCount photos.';
    }
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 80);
      if (file == null) return null;
      if (!isAllowedReportImageName(file.name)) {
        return 'Please choose a JPG, PNG, or WebP photo.';
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > kReportEvidenceMaxBytes) {
        return 'Each photo must be 5 MB or smaller.';
      }
      _evidence.add(
        ReportEvidenceDraft(
          bytes: bytes,
          name: file.name,
          contentType: reportImageContentType(file.name),
        ),
      );
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('OrderDeliveryReportController.addEvidence error: $e');
      return 'Could not add that photo.';
    }
  }

  void removeEvidence(int index) {
    if (index < 0 || index >= _evidence.length) return;
    _evidence.removeAt(index);
    _evidenceError = null;
    notifyListeners();
  }

  Future<({String? reportId, String? error})> submit() async {
    if (_isSubmitting) return (reportId: null, error: null);
    final order = _order;
    final reason = _reason;
    final uid = _auth.user?.id;
    if (order == null) return (reportId: null, error: 'Order not found.');
    if (reason == null) return (reportId: null, error: 'Choose a reason.');
    if (uid == null) return (reportId: null, error: 'Please sign in.');

    final detailsError = reportDetailsError(_details);
    if (detailsError != null) return (reportId: null, error: detailsError);

    if (_evidence.length < kReportEvidenceMinCount) {
      _evidenceError = 'Please attach at least one photo as evidence.';
      notifyListeners();
      return (reportId: null, error: _evidenceError);
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    String? reportId;
    try {
      final category = deliveryDisputeReportCategory(reason);
      final rpcRes = await _supabase.client.rpc(
        'submit_report',
        params: {
          'p_reported_user_id': order.sellerId,
          'p_category': category,
          'p_details': _details.trim(),
          'p_order_id': order.id,
        },
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        final error = supabaseRpcError(
          rpcRes,
          fallback: 'Could not submit this report.',
        );
        return (reportId: null, error: error);
      }
      reportId = supabaseRpcMap(rpcRes)?['report_id']?.toString();
      if (reportId == null || reportId.isEmpty) {
        return (reportId: null, error: 'Could not submit this report.');
      }

      final uploadError = await uploadReportEvidence(
        supabase: _supabase,
        uid: uid,
        reportId: reportId,
        evidence: _evidence,
      );
      if (uploadError != null) {
        await abandonOpenReport(_supabase, reportId);
        return (reportId: null, error: uploadError);
      }

      final disputeRes = await _supabase.client.rpc(
        'report_delivery_problem',
        params: {
          'p_order_id': order.id,
          'p_reason': reason.dbValue,
          'p_details': _details.trim(),
          'p_report_id': reportId,
        },
      );
      if (!supabaseRpcSuccess(disputeRes)) {
        return (
          reportId: reportId,
          error: supabaseRpcError(
            disputeRes,
            fallback:
                'Report saved, but the delivery dispute could not be opened.',
          ),
        );
      }

      return (reportId: reportId, error: null);
    } catch (e) {
      debugPrint('OrderDeliveryReportController.submit error: $e');
      if (reportId != null) {
        await abandonOpenReport(_supabase, reportId);
      }
      return (reportId: null, error: 'Could not submit this report.');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
