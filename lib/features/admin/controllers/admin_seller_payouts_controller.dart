import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_seller_payouts_service.dart';
import '../data/financial_evidence_storage.dart';
import '../domain/admin_seller_payout.dart';

class AdminSellerPayoutsController extends ChangeNotifier {
  AdminSellerPayoutsController({
    required SupabaseService supabase,
    AdminSellerPayoutsService? service,
    ImagePicker? picker,
    this.onWaitingCountChanged,
    AdminPayoutStatusFilter initialStatus = AdminPayoutStatusFilter.requested,
  }) : _service = service ?? AdminSellerPayoutsService(supabase),
       _picker = picker ?? ImagePicker(),
       _status = initialStatus {
    load();
  }

  final AdminSellerPayoutsService _service;
  final ImagePicker _picker;
  final ValueChanged<int>? onWaitingCountChanged;

  List<AdminSellerPayout> _rows = const [];
  AdminSellerPayoutCounts _counts = const AdminSellerPayoutCounts();
  int _total = 0;
  bool _isLoading = true;
  String? _errorMessage;
  AdminPayoutStatusFilter _status;
  String _search = '';
  int _page = 1;
  int _pageSize = 25;
  int _loadEpoch = 0;
  Timer? _searchDebounce;

  PickedEvidence? _evidence;
  bool _isSubmitting = false;
  String? _actionError;
  Map<String, String> _fieldErrors = const {};

  List<AdminSellerPayout> get rows => _rows;
  AdminSellerPayoutCounts get counts => _counts;
  int get total => _total;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AdminPayoutStatusFilter get status => _status;
  String get search => _search;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get hasActiveFilters =>
      _status != AdminPayoutStatusFilter.requested || _search.isNotEmpty;

  PickedEvidence? get evidence => _evidence;
  bool get isSubmitting => _isSubmitting;
  String? get actionError => _actionError;
  Map<String, String> get fieldErrors => _fieldErrors;

  Future<void> load() async {
    final epoch = ++_loadEpoch;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _service.list(
        status: _status,
        search: _search,
        limit: _pageSize,
        offset: (_page - 1) * _pageSize,
      );
      if (epoch != _loadEpoch) return;
      _rows = result.items;
      _total = result.total;
      _counts = result.counts;
      onWaitingCountChanged?.call(result.counts.requested);
    } catch (e) {
      if (epoch != _loadEpoch) return;
      debugPrint('AdminSellerPayoutsController.load error: $e');
      _errorMessage = 'Unable to load payouts. Try again.';
    } finally {
      if (epoch == _loadEpoch) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setStatus(AdminPayoutStatusFilter value) {
    if (_status == value) return;
    _status = value;
    _page = 1;
    load();
  }

  void scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => setSearch(value),
    );
  }

  void setSearch(String value) {
    final next = value.trim();
    if (next == _search) return;
    _search = next;
    _page = 1;
    load();
  }

  void setPage(int value) {
    if (value == _page || value < 1) return;
    _page = value;
    load();
  }

  void setPageSize(int value) {
    if (value == _pageSize) return;
    _pageSize = value;
    _page = 1;
    load();
  }

  void resetFilters() {
    _searchDebounce?.cancel();
    _status = AdminPayoutStatusFilter.requested;
    _search = '';
    _page = 1;
    load();
  }

  /// Clears the per-dialog form state before opening a payout.
  void beginAction() {
    _evidence = null;
    _actionError = null;
    _fieldErrors = const {};
    _isSubmitting = false;
    notifyListeners();
  }

  Future<void> pickEvidence() async {
    try {
      final file = await pickEvidenceImage(_picker);
      if (file == null) return;
      _evidence = file;
      _fieldErrors = Map.of(_fieldErrors)..remove('evidence');
      notifyListeners();
    } on EvidenceTooLargeException {
      _fieldErrors = {..._fieldErrors, 'evidence': 'Use a file under 5 MB.'};
      notifyListeners();
    } catch (e) {
      debugPrint('pick payout evidence error: $e');
      _fieldErrors = {
        ..._fieldErrors,
        'evidence': 'We could not open that file. Try another one.',
      };
      notifyListeners();
    }
  }

  void clearEvidence() {
    _evidence = null;
    notifyListeners();
  }

  /// Records a confirmed manual GCash transfer. Returns true on success.
  Future<bool> recordTransfer({
    required AdminSellerPayout payout,
    required String amountText,
    required String reference,
    required DateTime? sentAt,
    String? note,
  }) async {
    if (_isSubmitting) return false;
    final errors = <String, String>{
      if (validateTransferAmount(amountText, payout.amountCentavos)
          case final e?)
        'amount': e,
      if (validateTransferReference(reference) case final e?) 'reference': e,
      if (validateTransferDate(sentAt) case final e?) 'date': e,
      if (_evidence == null) 'evidence': 'Attach the GCash receipt.',
    };
    if (!payout.isOpen) {
      _actionError = 'This payout is no longer waiting for a transfer.';
    }
    _fieldErrors = errors;
    if (errors.isNotEmpty || !payout.isOpen) {
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _actionError = null;
    notifyListeners();
    String? uploadedPath;
    try {
      uploadedPath = await _service.evidence.upload(
        folder: 'payouts',
        ownerId: payout.sellerId,
        file: _evidence!,
      );
      final error = await _service.markPaid(
        payoutId: payout.payoutId,
        transferredAmountCentavos: parsePesoToCentavos(amountText)!,
        reference: reference,
        transferredAt: sentAt!,
        evidencePath: uploadedPath,
        note: note,
      );
      if (error != null) {
        _actionError = error;
        await _bestEffortRemove(uploadedPath);
        return false;
      }
      _evidence = null;
      await load();
      return true;
    } catch (e) {
      debugPrint('record payout transfer error: $e');
      _actionError = uploadedPath == null
          ? 'We could not upload the receipt. Try again.'
          : 'We could not record this transfer. Try again.';
      if (uploadedPath != null) await _bestEffortRemove(uploadedPath);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> reject({
    required AdminSellerPayout payout,
    required String reason,
  }) async {
    if (_isSubmitting) return false;
    final reasonError = validateRejectionReason(reason.trim());
    _fieldErrors = {if (reasonError != null) 'reason': reasonError};
    if (reasonError != null) {
      notifyListeners();
      return false;
    }
    _isSubmitting = true;
    _actionError = null;
    notifyListeners();
    try {
      final trimmed = reason.trim();
      final error = await _service.reject(
        payoutId: payout.payoutId,
        reason: trimmed,
      );
      if (error != null) {
        _actionError = error;
        return false;
      }
      await load();
      return true;
    } catch (e) {
      debugPrint('reject payout error: $e');
      _actionError = 'We could not reject this payout. Try again.';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Opens a short-lived signed link to a private receipt.
  Future<bool> openEvidence(String path) async {
    try {
      final url = await _service.evidence.signedUrl(path);
      return await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      debugPrint('open payout evidence error: $e');
      return false;
    }
  }

  Future<void> _bestEffortRemove(String path) async {
    try {
      await _service.evidence.remove(path);
    } catch (e) {
      debugPrint('remove payout evidence error: $e');
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
