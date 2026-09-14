import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_delivery_dispute.dart';
import '../data/admin_review_rules.dart';
import '../data/admin_review_service.dart';
import '../data/delivery_payment_resolve.dart';

class AdminDisputesController extends ChangeNotifier {
  AdminDisputesController({required SupabaseService supabase, this.disputeId})
    : _service = AdminReviewService(supabase) {
    load();
  }

  final AdminReviewService _service;
  final String? disputeId;

  AdminQueueFilter _filter = AdminQueueFilter.open;
  List<AdminDeliveryDispute> _disputes = const [];
  AdminDeliveryDispute? _dispute;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  final TextEditingController noteController = TextEditingController();

  AdminQueueFilter get filter => _filter;
  List<AdminDeliveryDispute> get disputes => _disputes;
  AdminDeliveryDispute? get dispute => _dispute;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get note => noteController.text;
  bool get canSubmitClose =>
      _dispute != null &&
      canCloseDispute(_dispute!.status) &&
      adminDisputeNoteError(note) == null &&
      !_isSaving;

  bool get canSubmitPaymentDecision {
    final hold = _dispute?.paymentHold;
    return hold != null &&
        hold.canDecide &&
        adminDisputeNoteError(note) == null &&
        !_isSaving;
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void setFilter(AdminQueueFilter value) {
    if (_filter == value) return;
    _filter = value;
    load();
  }

  void setNote(String value) {
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (disputeId != null) {
        _dispute = await _service.getDispute(disputeId!);
        if (_dispute == null) {
          _errorMessage = 'Delivery problem not found.';
        } else {
          final saved = _dispute!.adminNote;
          if (saved != null &&
              saved.isNotEmpty &&
              noteController.text.isEmpty) {
            noteController.text = saved;
          }
        }
      } else {
        _disputes = await _service.listDisputes(filter: _filter);
      }
    } catch (e) {
      debugPrint('AdminDisputesController.load error: $e');
      _disputes = const [];
      _dispute = null;
      _errorMessage = disputeId == null
          ? 'Unable to load delivery problems.'
          : 'Unable to load this delivery problem.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> closeCase() async {
    final current = _dispute;
    if (current == null) return 'Delivery problem not found.';
    if (!canCloseDispute(current.status)) {
      return 'This delivery problem is already closed.';
    }
    final noteError = adminDisputeNoteError(note);
    if (noteError != null) return noteError;
    if (_isSaving) return null;

    _isSaving = true;
    notifyListeners();
    try {
      final error = await _service.closeDeliveryDispute(
        disputeId: current.id,
        adminNote: note,
      );
      if (error != null) return error;
      await load();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<DeliveryPaymentResult> _runPaymentDecision(
    Future<DeliveryPaymentResult> Function() action,
  ) async {
    final current = _dispute;
    if (current == null) {
      return const DeliveryPaymentResult(
        success: false,
        error: 'Delivery problem not found.',
      );
    }
    if (!canSubmitPaymentDecision) {
      return const DeliveryPaymentResult(
        success: false,
        error: 'This payment cannot be updated.',
      );
    }

    _isSaving = true;
    notifyListeners();
    try {
      final result = await action();
      if (result.success) await load();
      return result;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<DeliveryPaymentResult> releasePayment() {
    return _runPaymentDecision(
      () => _service.releaseDeliveryPayment(
        disputeId: _dispute!.id,
        adminNote: note,
      ),
    );
  }

  Future<DeliveryPaymentResult> refundPayment() {
    return _runPaymentDecision(
      () => _service.refundDeliveryPayment(
        disputeId: _dispute!.id,
        adminNote: note,
      ),
    );
  }
}
