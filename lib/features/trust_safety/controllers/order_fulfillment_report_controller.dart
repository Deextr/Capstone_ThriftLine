import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/fulfillment_sla.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/report_evidence_upload.dart';
import '../data/report_reasons.dart';
import 'report_user_controller.dart';

class OrderFulfillmentReportController extends ChangeNotifier {
  OrderFulfillmentReportController({
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
  ReportReason? _reason = fulfillmentBuyerReportReasons().first;
  String _details = '';
  final List<ReportEvidenceDraft> _evidence = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _evidenceError;

  OrderModel? get order => _order;
  ReportReason? get reason => _reason;
  String get details => _details;
  List<ReportEvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get evidenceError => _evidenceError;
  List<ReportReason> get reasons => fulfillmentBuyerReportReasons();

  bool get detailsRequired => _reason?.slug == 'other';

  String? get _detailsValidationError => communityReportDetailsError(
    _details,
    detailsRequired ? 'other' : null,
  );

  bool get canSubmit {
    if (_isSubmitting || _order == null || _reason == null) return false;
    if (_detailsValidationError != null) {
      return false;
    }
    if (_evidence.length < kReportEvidenceMinCount) return false;
    return fulfillmentSlaForOrder(_order!).canSubmitFulfillmentReport;
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
        return;
      }
      final sla = fulfillmentSlaForOrder(_order!);
      if (sla.cta == FulfillmentReportCta.waiting) {
        _errorMessage =
            'You can report a shipping delay after 48 hours if the seller has not updated this order.';
      } else if (sla.cta == FulfillmentReportCta.hidden) {
        _errorMessage =
            'This order is no longer waiting on the seller to prepare it.';
      } else if (sla.cta == FulfillmentReportCta.underReview) {
        _errorMessage = 'You already have an active report for this order.';
      }
    } catch (e) {
      debugPrint('OrderFulfillmentReportController.load error: $e');
      _errorMessage = 'Unable to load this order.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectReason(ReportReason reason) {
    _reason = reason;
    notifyListeners();
  }

  void setDetails(String value) {
    if (value.length > kReportDetailsMaxLength) return;
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
      debugPrint('OrderFulfillmentReportController.addEvidence error: $e');
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

    final detailsError = _detailsValidationError;
    if (detailsError != null) {
      return (reportId: null, error: detailsError);
    }

    if (_evidence.length < kReportEvidenceMinCount) {
      _evidenceError = 'Please attach at least one photo as evidence.';
      notifyListeners();
      return (reportId: null, error: _evidenceError);
    }

    if (!fulfillmentSlaForOrder(order).canSubmitFulfillmentReport) {
      return (
        reportId: null,
        error:
            'You can report a shipping delay 48 hours after payment if the seller has not updated this order.',
      );
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    String? reportId;
    try {
      final rpcRes = await _supabase.client.rpc(
        'submit_report',
        params: {
          'p_reported_user_id': order.sellerId,
          'p_category': reason.slug,
          'p_details': _details.trim(),
          'p_order_id': order.id,
        },
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return (
          reportId: null,
          error: supabaseRpcError(
            rpcRes,
            fallback: 'Could not submit this report.',
          ),
        );
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

      return (reportId: reportId, error: null);
    } catch (e) {
      debugPrint('OrderFulfillmentReportController.submit error: $e');
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
