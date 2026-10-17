import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../buyer/data/buyer_transaction.dart'
    show
        normalizePhMobileNumber,
        validateGcashAccountName,
        validateGcashMobileNumber;
import '../data/admin_refunds_service.dart';
import '../data/delivery_payment_hold.dart';
import '../data/financial_evidence_storage.dart';
import '../domain/admin_refund.dart';
import '../domain/admin_seller_payout.dart'
    show parsePesoToCentavos, validateTransferAmount, validateTransferReference;

enum AdminRefundAction { check, retry, manual }

/// Refund follow-up for one escrow: record manual GCash refunds with proof and
/// read legacy PayMongo status when applicable. Never sends money itself.
class AdminRefundController extends ChangeNotifier {
  AdminRefundController({
    required SupabaseService supabase,
    required DeliveryPaymentHold hold,
    AdminRefundsService? service,
    ImagePicker? picker,
    this.onRefundChanged,
  }) : _hold = hold,
       _service = service ?? AdminRefundsService(supabase),
       _picker = picker ?? ImagePicker() {
    load();
  }

  DeliveryPaymentHold _hold;
  final AdminRefundsService _service;
  final ImagePicker _picker;

  /// Called after PayMongo or a manual record changed the refund.
  final VoidCallback? onRefundChanged;

  AdminRefundDetails? _details;
  List<AdminRefundAttempt> _attempts = const [];
  bool _isLoading = true;
  String? _loadError;
  AdminRefundAction? _busy;
  String? _actionError;
  String? _actionMessage;
  bool _showManualForm = false;
  PickedEvidence? _evidence;
  Map<String, String> _fieldErrors = const {};
  bool _disposed = false;

  DeliveryPaymentHold get hold => _hold;
  AdminRefundDetails? get details => _details;
  List<AdminRefundAttempt> get attempts => _attempts;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  AdminRefundAction? get busyAction => _busy;
  bool get isBusy => _busy != null;
  String? get actionError => _actionError;
  String? get actionMessage => _actionMessage;
  bool get showManualForm => _showManualForm;
  PickedEvidence? get evidence => _evidence;
  Map<String, String> get fieldErrors => _fieldErrors;

  String get _state => hold.refundState ?? '';

  bool get _legacyPaymongoRefund =>
      hold.refundProvider == 'paymongo' &&
      (hold.paymongoRefundId?.isNotEmpty ?? false);

  /// Read-only sync for older PayMongo refund rows still in flight.
  bool get canCheckProvider =>
      _legacyPaymongoRefund &&
      (_state == 'provider_pending' || _state == 'awaiting_buyer_claim');

  bool get canRetryProvider => false;

  bool get canRecordManual => _state == 'manual_required' && !hold.refundLocked;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      final snapshot = await _service.load(_hold.escrowId);
      if (snapshot.hold != null) _hold = snapshot.hold!;
      _details = snapshot.details;
      _attempts = snapshot.attempts;
    } catch (e) {
      debugPrint('AdminRefundController.load error: $e');
      _loadError = 'Unable to load refund details.';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> checkProvider() => _reconcile(AdminRefundAction.check, 'check');

  Future<void> retryProvider() => _reconcile(AdminRefundAction.retry, 'retry');

  Future<void> _reconcile(AdminRefundAction action, String rpcAction) async {
    if (isBusy) return;
    _busy = action;
    _actionError = null;
    _actionMessage = null;
    _notify();
    try {
      final result = await _service.reconcile(
        escrowId: hold.escrowId,
        action: rpcAction,
      );
      if (result.success) {
        _actionMessage = result.message;
      } else {
        _actionError = result.message;
      }
      await load();
      onRefundChanged?.call();
    } catch (e) {
      debugPrint('AdminRefundController.$rpcAction error: $e');
      _actionError = 'PayMongo could not be reached. Nothing was changed.';
    } finally {
      _busy = null;
      _notify();
    }
  }

  void toggleManualForm(bool open) {
    _showManualForm = open;
    _fieldErrors = const {};
    _actionError = null;
    if (!open) _evidence = null;
    _notify();
  }

  Future<void> pickEvidence() async {
    try {
      final file = await pickEvidenceImage(_picker);
      if (file == null) return;
      _evidence = file;
      _fieldErrors = Map.of(_fieldErrors)..remove('evidence');
    } on EvidenceTooLargeException {
      _fieldErrors = {..._fieldErrors, 'evidence': 'Use a file under 5 MB.'};
    } catch (e) {
      debugPrint('pick refund evidence error: $e');
      _fieldErrors = {
        ..._fieldErrors,
        'evidence': 'We could not open that file. Try another one.',
      };
    }
    _notify();
  }

  /// Records a GCash refund the admin already sent. Returns true on success.
  Future<bool> recordManualRefund({
    required String amountText,
    required String reference,
    required DateTime? sentAt,
    required String accountName,
    required String mobileNumber,
    String? note,
  }) async {
    if (isBusy) return false;
    final buyerId = hold.buyerId;
    final errors = <String, String>{
      if (validateTransferAmount(amountText, hold.amountCentavos) case final e?)
        'amount': e,
      if (validateTransferReference(reference) case final e?) 'reference': e,
      if (_validateSentAt(sentAt) case final e?) 'date': e,
      if (validateGcashAccountName(accountName) case final e?) 'name': e,
      if (validateGcashMobileNumber(mobileNumber) case final e?) 'mobile': e,
      if (_evidence == null) 'evidence': 'Attach the GCash receipt.',
    };
    _fieldErrors = errors;
    if (!canRecordManual) {
      _actionError = 'This refund is not waiting for a manual transfer.';
    } else if (buyerId == null) {
      _actionError = 'The buyer for this refund could not be found.';
    }
    if (errors.isNotEmpty || !canRecordManual || buyerId == null) {
      _notify();
      return false;
    }

    _busy = AdminRefundAction.manual;
    _actionError = null;
    _actionMessage = null;
    _notify();
    String? uploadedPath;
    try {
      uploadedPath = await _service.evidence.upload(
        folder: 'refunds',
        ownerId: buyerId,
        file: _evidence!,
      );
      final error = await _service.recordManualRefund(
        escrowId: hold.escrowId,
        amountCentavos: parsePesoToCentavos(amountText)!,
        reference: reference,
        sentAt: sentAt!,
        evidencePath: uploadedPath,
        accountName: accountName,
        mobileNumber: normalizePhMobileNumber(mobileNumber)!,
        note: note,
      );
      if (error != null) {
        _actionError = error;
        await _bestEffortRemove(uploadedPath);
        return false;
      }
      _evidence = null;
      _showManualForm = false;
      _actionMessage = 'Manual GCash refund recorded. The buyer can see it.';
      await load();
      onRefundChanged?.call();
      return true;
    } catch (e) {
      debugPrint('record manual refund error: $e');
      _actionError = uploadedPath == null
          ? 'We could not upload the receipt. Try again.'
          : 'We could not record this refund. Try again.';
      if (uploadedPath != null) await _bestEffortRemove(uploadedPath);
      return false;
    } finally {
      _busy = null;
      _notify();
    }
  }

  Future<bool> openEvidence(String path) async {
    try {
      final url = await _service.evidence.signedUrl(path);
      return await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      debugPrint('open refund evidence error: $e');
      return false;
    }
  }

  String? _validateSentAt(DateTime? sentAt) {
    if (sentAt == null) return 'Choose the date you sent the refund.';
    if (sentAt.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
      return 'The date cannot be in the future.';
    }
    return null;
  }

  Future<void> _bestEffortRemove(String path) async {
    try {
      await _service.evidence.remove(path);
    } catch (e) {
      debugPrint('remove refund evidence error: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
