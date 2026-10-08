import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/community_report_model.dart';
import '../../../models/order_model.dart';
import '../../buyer/data/order_query.dart';
import '../../trust_safety/data/report_reasons.dart';
import '../data/admin_dashboard_models.dart';
import '../data/admin_delivery_dispute.dart';
import '../data/admin_review_rules.dart';
import '../data/admin_review_service.dart';
import '../data/delivery_payment_hold.dart';
import '../data/delivery_payment_resolve.dart';
import '../data/looking_for_moderation.dart';

class AdminReportKindSummary {
  const AdminReportKindSummary({
    required this.total,
    required this.underReview,
    required this.needsMoreEvidence,
    required this.resolved,
    required this.dismissed,
  });

  final int total;
  final int underReview;
  final int needsMoreEvidence;
  final int resolved;
  final int dismissed;

  int countFor(AdminReportListFilter filter) => switch (filter) {
    AdminReportListFilter.all => total,
    AdminReportListFilter.underReview => underReview,
    AdminReportListFilter.needsMoreEvidence => needsMoreEvidence,
    AdminReportListFilter.resolved => resolved,
    AdminReportListFilter.dismissed => dismissed,
  };
}

class AdminReportsController extends ChangeNotifier {
  AdminReportsController({required SupabaseService supabase, this.reportId})
    : _supabase = supabase,
      _service = AdminReviewService(supabase),
      _lookingFor = LookingForModerationService(supabase) {
    load();
  }

  final SupabaseService _supabase;
  final AdminReviewService _service;
  final LookingForModerationService _lookingFor;
  final String? reportId;

  AdminReportListFilter _filter = AdminReportListFilter.all;
  AdminReportKind _kind = AdminReportKind.all;
  AdminReportSort _sort = AdminReportSort.newest;
  AdminDateWindow? _dateWindow;
  List<CommunityReportModel> _reports = const [];
  List<LookingForAdminReport> _lookingForReports = const [];
  CommunityReportModel? _report;
  OrderModel? _relatedOrder;
  AdminDeliveryDispute? _relatedDispute;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _decision;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController responseController = TextEditingController();

  AdminReportListFilter get filter => _filter;
  AdminReportKind get kind => _kind;
  AdminReportSort get sort => _sort;
  AdminDateWindow? get dateWindow => _dateWindow;
  List<CommunityReportModel> get reports => _reports;
  List<LookingForAdminReport> get lookingForReports => _lookingForReports;
  CommunityReportModel? get report => _report;
  OrderModel? get relatedOrder => _relatedOrder;
  AdminDeliveryDispute? get relatedDispute => _relatedDispute;
  DeliveryPaymentHold? get paymentHold => _relatedDispute?.paymentHold;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get decision => _decision;
  String get searchQuery => searchController.text;
  String get response => responseController.text;
  bool get isOrderReport =>
      _report != null &&
      isAdminOrderReport(
        category: _report!.category,
        orderId: _report!.orderId,
      );

  bool get canSubmitDecision =>
      _report != null &&
      canDecideReport(_report!.status) &&
      !isOrderReport &&
      _decision != null &&
      adminResponseError(response, decision: _decision) == null &&
      !_isSaving;

  String? get orderResolutionNotesError {
    if (response.trim().isEmpty) return null;
    return adminResponseError(response, decision: 'resolved');
  }

  bool get canSubmitOrderFinancialResolution {
    return isOrderReport &&
        canDecideReport(_report!.status) &&
        relatedDispute != null &&
        paymentHold != null &&
        orderResolutionNotesError == null &&
        response.trim().length >= kAdminResponseMinLength &&
        !_isSaving;
  }

  bool get hasActiveListFilters =>
      _filter != AdminReportListFilter.all ||
      _dateWindow != null ||
      searchQuery.trim().isNotEmpty;

  AdminReportKindSummary get activeKindSummary => kindSummary(_kind);

  int get totalCount => activeKindSummary.total;
  int get underReviewCount => activeKindSummary.underReview;
  int get resolvedCount => activeKindSummary.resolved;
  int get needsMoreEvidenceCount => activeKindSummary.needsMoreEvidence;
  int get dismissedCount => activeKindSummary.dismissed;

  AdminReportKindSummary kindSummary(AdminReportKind kind) {
    if (kind == AdminReportKind.lookingFor) {
      return _summaryForLookingFor(_lookingForReports);
    }
    if (kind == AdminReportKind.all) {
      final community = kindSummary(AdminReportKind.community);
      final orders = kindSummary(AdminReportKind.order);
      final lookingFor = kindSummary(AdminReportKind.lookingFor);
      return AdminReportKindSummary(
        total: community.total + orders.total + lookingFor.total,
        underReview:
            community.underReview + orders.underReview + lookingFor.underReview,
        needsMoreEvidence:
            community.needsMoreEvidence +
            orders.needsMoreEvidence +
            lookingFor.needsMoreEvidence,
        resolved: community.resolved + orders.resolved + lookingFor.resolved,
        dismissed:
            community.dismissed + orders.dismissed + lookingFor.dismissed,
      );
    }
    return _summaryForCommunity(
      _reports.where((report) => _reportMatchesKind(report, kind)),
    );
  }

  AdminReportKindSummary _summaryForCommunity(
    Iterable<CommunityReportModel> items,
  ) {
    final list = items.toList();
    return AdminReportKindSummary(
      total: list.length,
      underReview: list
          .where((item) => item.status == kAdminReportOpenStatus)
          .length,
      needsMoreEvidence: list
          .where((item) => item.status == kAdminReportNeedsEvidenceStatus)
          .length,
      resolved: list.where((item) => item.status == 'resolved').length,
      dismissed: list.where((item) => item.status == 'dismissed').length,
    );
  }

  AdminReportKindSummary _summaryForLookingFor(
    Iterable<LookingForAdminReport> items,
  ) {
    final list = items.toList();
    return AdminReportKindSummary(
      total: list.length,
      underReview: list
          .where((item) => item.status == kAdminReportOpenStatus)
          .length,
      needsMoreEvidence: list
          .where((item) => item.status == kAdminReportNeedsEvidenceStatus)
          .length,
      resolved: list.where((item) => item.status == 'resolved').length,
      dismissed: list.where((item) => item.status == 'dismissed').length,
    );
  }

  bool _reportMatchesKind(CommunityReportModel report, AdminReportKind kind) {
    final isOrder = isAdminOrderReport(
      category: report.category,
      orderId: report.orderId,
    );
    return switch (kind) {
      AdminReportKind.community => !isOrder,
      AdminReportKind.order => isOrder,
      AdminReportKind.lookingFor => false,
      AdminReportKind.all => true,
    };
  }

  List<CommunityReportModel> get visibleReports {
    final query = searchQuery.trim().toLowerCase();
    final statuses = adminReportListFilterStatuses(_filter);
    final filtered = _reports.where((report) {
      final isOrder = isAdminOrderReport(
        category: report.category,
        orderId: report.orderId,
      );
      if (_kind == AdminReportKind.community && isOrder) return false;
      if (_kind == AdminReportKind.order && !isOrder) return false;
      if (statuses != null && !statuses.contains(report.status)) return false;
      if (query.isEmpty) return true;
      final haystack = [
        adminReportShortId(report.id),
        report.id,
        reportReasonLabel(report.category),
        adminHandle(report.reporterUsername, report.reporterDisplayName),
        adminHandle(report.reportedUsername, report.reportedDisplayName),
        report.reporterDisplayName,
        report.reportedDisplayName,
        report.orderNumber ?? '',
        report.details,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final comparison = a.createdAt.compareTo(b.createdAt);
      return _sort == AdminReportSort.newest ? -comparison : comparison;
    });
    return filtered;
  }

  List<LookingForAdminReport> get visibleLookingForReports {
    final query = searchQuery.trim().toLowerCase();
    final statuses = adminReportListFilterStatuses(_filter);
    final filtered = _lookingForReports.where((report) {
      if (statuses != null && !statuses.contains(report.status)) return false;
      final created = report.createdAt;
      final window = _dateWindow;
      if (window != null) {
        if (created.isBefore(window.from)) return false;
        if (!created.isBefore(window.toExclusive)) return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        report.postTitle,
        report.reason,
        report.details,
        report.reporterName,
        report.reporterUsername,
        report.reportedName,
        report.reportedUsername,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    filtered.sort((a, b) {
      final comparison = a.createdAt.compareTo(b.createdAt);
      return _sort == AdminReportSort.newest ? -comparison : comparison;
    });
    return filtered;
  }

  bool matchesKind(CommunityReportModel report) =>
      _reportMatchesKind(report, _kind);

  void openCategoryList(AdminReportKind kind) {
    if (kind == AdminReportKind.all) return;
    _kind = kind;
    _filter = AdminReportListFilter.all;
    searchController.clear();
    notifyListeners();
  }

  void leaveCategoryList() {
    _kind = AdminReportKind.all;
    _filter = AdminReportListFilter.all;
    searchController.clear();
    notifyListeners();
  }

  void clearListFilters() {
    _filter = AdminReportListFilter.all;
    _dateWindow = null;
    searchController.clear();
    notifyListeners();
    load();
  }

  @override
  void dispose() {
    searchController.dispose();
    responseController.dispose();
    super.dispose();
  }

  void setFilter(AdminReportListFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setKind(AdminReportKind value) {
    if (_kind == value) return;
    _kind = value;
    notifyListeners();
  }

  void setSort(AdminReportSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  void setSearch(String _) {
    notifyListeners();
  }

  void setDateWindow(AdminDateWindow? value) {
    _dateWindow = value;
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
        _relatedDispute = null;
        if (_report == null) {
          _errorMessage = 'Report not found.';
        } else if (_report!.orderId != null && _report!.orderId!.isNotEmpty) {
          _relatedOrder = await fetchOrderById(_supabase, _report!.orderId!);
          _relatedDispute = await _service.getDisputeForOrderReport(
            disputeId: _report!.disputeId,
            orderId: _report!.orderId,
          );
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
        _reports = await _service.listReports(
          filter: AdminReportListFilter.all,
          from: _dateWindow?.from,
          toExclusive: _dateWindow?.toExclusive,
        );
        try {
          _lookingForReports = await _lookingFor.listReports();
        } catch (e) {
          debugPrint('AdminReportsController looking for reports error: $e');
          _lookingForReports = const [];
        }
      }
    } catch (e) {
      debugPrint('AdminReportsController.load error: $e');
      _reports = const [];
      _report = null;
      _relatedOrder = null;
      _relatedDispute = null;
      _errorMessage = reportId == null
          ? 'Unable to load reports.'
          : 'Unable to load this report.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> submitOrderEvidenceRequest({
    required String party,
    required String instruction,
  }) async {
    final current = _report;
    if (current == null) return 'Report not found.';
    if (!canDecideReport(current.status)) {
      return 'This report is already closed.';
    }
    if (_isSaving) return null;
    _isSaving = true;
    notifyListeners();
    try {
      return await _service
          .requestOrderReportEvidence(
            reportId: current.id,
            party: party,
            instruction: instruction,
          )
          .then((error) async {
            if (error == null) await load();
            return error;
          });
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<DeliveryPaymentResult> confirmOrderFinancialResolution({
    required bool refundBuyer,
    required bool? returnRequired,
  }) async {
    if (_relatedDispute == null) {
      return const DeliveryPaymentResult(
        success: false,
        error: 'No delivery dispute is linked to this order report.',
      );
    }
    final notesError = adminResponseError(response, decision: 'resolved');
    if (notesError != null) {
      return DeliveryPaymentResult(success: false, error: notesError);
    }
    if (_isSaving) {
      return const DeliveryPaymentResult(success: false, error: 'Please wait…');
    }

    _isSaving = true;
    notifyListeners();
    try {
      DeliveryPaymentResult result;
      if (refundBuyer) {
        if (returnRequired == null) {
          return const DeliveryPaymentResult(
            success: false,
            error: 'Choose whether the item must be returned.',
          );
        }
        final hold = paymentHold;
        if (hold != null && hold.isRefunded) {
          result = await _service.refundDeliveryPayment(
            disputeId: _relatedDispute!.id,
            adminNote: response.trim(),
            returnRequired: returnRequired,
          );
          if (!result.success) return result;
        } else {
          result = await _service.refundDeliveryPayment(
            disputeId: _relatedDispute!.id,
            adminNote: response.trim(),
            returnRequired: returnRequired,
          );
          if (!result.success) return result;
        }
        final closeError = await _service.completeOrderReportResolution(
          reportId: _report!.id,
          financial: 'refund_buyer',
          adminResponse: response,
          returnRequired: returnRequired,
        );
        if (closeError != null) {
          return DeliveryPaymentResult(success: false, error: closeError);
        }
      } else {
        final hold = paymentHold;
        if (hold != null && hold.isReleased) {
          result = DeliveryPaymentResult(
            success: true,
            alreadyDecided: true,
            decision: 'release',
            status: 'released',
          );
        } else {
          result = await _service.releaseDeliveryPayment(
            disputeId: _relatedDispute!.id,
            adminNote: response.trim(),
          );
        }
        if (!result.success) return result;
        final closeError = await _service.completeOrderReportResolution(
          reportId: _report!.id,
          financial: 'release_seller',
          adminResponse: response,
        );
        if (closeError != null) {
          return DeliveryPaymentResult(success: false, error: closeError);
        }
      }
      await load();
      return result;
    } finally {
      _isSaving = false;
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
    if (isOrderReport && selected != 'needs_more_evidence') {
      return 'Use the financial resolution controls for this order report.';
    }
    final responseError = adminResponseError(response, decision: _decision);
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
