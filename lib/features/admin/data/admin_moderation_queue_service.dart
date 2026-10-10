import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/community_report_model.dart';
import 'admin_delivery_dispute.dart';
import 'admin_review_rules.dart';
import 'admin_review_service.dart';
import '../domain/looking_for_report_moderation.dart';
import 'looking_for_moderation.dart';

class AdminModerationCaseRow {
  const AdminModerationCaseRow({
    required this.source,
    required this.caseId,
    required this.caseKind,
    required this.category,
    required this.summary,
    required this.statusRaw,
    required this.actorName,
    required this.subjectName,
    this.orderNumber,
    required this.createdAt,
    this.lfPostTitle,
    this.lfExpiresAt,
    this.lfOpenReports,
    this.lfPriorityScore,
    this.lfDecisionOutcome,
  });

  final String source;
  final String caseId;
  final String caseKind;
  final String category;
  final String summary;
  final String statusRaw;
  final String actorName;
  final String subjectName;
  final String? orderNumber;
  final DateTime createdAt;
  final String? lfPostTitle;
  final DateTime? lfExpiresAt;
  final int? lfOpenReports;
  final int? lfPriorityScore;
  final String? lfDecisionOutcome;

  bool get isLookingForReport =>
      caseKind == 'looking_for_report' || source == 'looking_for';

  factory AdminModerationCaseRow.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(Object? value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return AdminModerationCaseRow(
      source: (json['source'] as String?)?.trim() ?? '',
      caseId: (json['case_id'] as String?)?.trim() ?? '',
      caseKind: (json['case_kind'] as String?)?.trim() ?? '',
      category: (json['category'] as String?)?.trim() ?? '',
      summary: (json['summary'] as String?)?.trim() ?? '',
      statusRaw: (json['status_raw'] as String?)?.trim() ?? '',
      actorName: (json['actor_name'] as String?)?.trim() ?? 'Member',
      subjectName: (json['subject_name'] as String?)?.trim() ?? 'Member',
      orderNumber: (json['order_number'] as String?)?.trim(),
      createdAt: parseTime(json['created_at']) ?? DateTime.now(),
      lfPostTitle: (json['lf_post_title'] as String?)?.trim(),
      lfExpiresAt: parseTime(json['lf_expires_at']),
      lfOpenReports: (json['lf_open_reports'] as num?)?.toInt(),
      lfPriorityScore: (json['lf_priority_score'] as num?)?.toInt(),
      lfDecisionOutcome: (json['lf_decision_outcome'] as String?)?.trim(),
    );
  }

  static AdminModerationCaseRow fromReport(CommunityReportModel report) {
    final orderLinked = isAdminOrderReport(
      category: report.category,
      orderId: report.orderId,
    );
    return AdminModerationCaseRow(
      source: 'report',
      caseId: report.id,
      caseKind: orderLinked ? 'order_report' : 'community_report',
      category: report.category,
      summary: adminReportPreview(report.details),
      statusRaw: report.status,
      actorName: report.reporterDisplayName,
      subjectName: report.reportedDisplayName,
      orderNumber: report.orderNumber,
      createdAt: report.createdAt,
    );
  }

  static AdminModerationCaseRow fromDeliveryDispute(
    AdminDeliveryDispute dispute,
  ) {
    return AdminModerationCaseRow(
      source: 'delivery_dispute',
      caseId: dispute.id,
      caseKind: 'delivery_dispute',
      category: dispute.reason.name,
      summary: adminReportPreview(dispute.details ?? ''),
      statusRaw: dispute.status,
      actorName: dispute.buyerDisplayName.isNotEmpty
          ? dispute.buyerDisplayName
          : dispute.buyerUsername,
      subjectName: dispute.sellerDisplayName.isNotEmpty
          ? dispute.sellerDisplayName
          : dispute.sellerUsername,
      orderNumber: dispute.orderNumber,
      createdAt: dispute.createdAt,
    );
  }

  static AdminModerationCaseRow fromLookingFor(
    LookingForAdminReport report, {
    DateTime? serverNow,
  }) {
    final now = serverNow ?? DateTime.now().toUtc();
    return AdminModerationCaseRow(
      source: 'looking_for',
      caseId: report.id,
      caseKind: 'looking_for_report',
      category: report.reason,
      summary: adminReportPreview(report.details),
      statusRaw: report.status,
      actorName: report.reporterName,
      subjectName: report.reportedName,
      orderNumber: null,
      createdAt: report.createdAt,
      lfPostTitle: report.displayPostTitle,
      lfExpiresAt: report.expiresAt,
      lfOpenReports: report.openReportsOnPost,
      lfPriorityScore: lookingForReportPriorityScore(
        reason: report.reason,
        status: report.status,
        expiresAt: report.expiresAt,
        reportCreatedAt: report.createdAt,
        openReportsOnPost: report.openReportsOnPost,
        confirmedViolations: report.confirmedViolations,
        serverNow: now,
      ),
      lfDecisionOutcome: report.decisionOutcome,
    );
  }
}

class AdminModerationQueuePage {
  const AdminModerationQueuePage({required this.items, required this.total});

  final List<AdminModerationCaseRow> items;
  final int total;
}

class AdminModerationQueueService {
  AdminModerationQueueService(this._supabase)
    : _review = AdminReviewService(_supabase),
      _lookingFor = LookingForModerationService(_supabase);

  final SupabaseService _supabase;
  final AdminReviewService _review;
  final LookingForModerationService _lookingFor;

  Future<AdminModerationQueuePage> list({
    required AdminModerationCategory category,
    required AdminReportListFilter statusFilter,
    AdminLookingForLifecycleFilter lfLifecycleFilter =
        AdminLookingForLifecycleFilter.all,
    required int page,
    required int pageSize,
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    try {
      return await _listViaRpc(
        category: category,
        statusFilter: statusFilter,
        lfLifecycleFilter: lfLifecycleFilter,
        page: page,
        pageSize: pageSize,
        search: search,
        from: from,
        toExclusive: toExclusive,
      );
    } catch (e, st) {
      debugPrint('AdminModerationQueueService RPC error: $e\n$st');
      return _listViaFallback(
        category: category,
        statusFilter: statusFilter,
        lfLifecycleFilter: lfLifecycleFilter,
        page: page,
        pageSize: pageSize,
        search: search,
        from: from,
        toExclusive: toExclusive,
      );
    }
  }

  Future<AdminModerationQueuePage> _listViaRpc({
    required AdminModerationCategory category,
    required AdminReportListFilter statusFilter,
    required AdminLookingForLifecycleFilter lfLifecycleFilter,
    required int page,
    required int pageSize,
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    final offset = page * pageSize;
    final raw = await _supabase.client.rpc(
      'admin_moderation_queue',
      params: {
        'p_category': adminModerationCategoryParam(category),
        'p_status': adminModerationStatusFilterParam(statusFilter),
        'p_search': search?.trim().isNotEmpty == true ? search!.trim() : null,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': toExclusive?.toUtc().toIso8601String(),
        'p_limit': pageSize,
        'p_offset': offset,
        'p_lf_lifecycle': adminLookingForLifecycleFilterParam(
          lfLifecycleFilter,
        ),
      },
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] != true) {
      throw StateError(
        supabaseRpcError(map, fallback: 'Moderation queue unavailable.') ??
            'Moderation queue unavailable.',
      );
    }
    final itemsRaw = map['items'];
    final list = itemsRaw is List ? itemsRaw : const [];
    return AdminModerationQueuePage(
      items: [
        for (final item in list)
          if (item is Map<String, dynamic>)
            AdminModerationCaseRow.fromJson(item)
          else if (item is Map)
            AdminModerationCaseRow.fromJson(Map<String, dynamic>.from(item)),
      ],
      total: _asInt(map['total']),
    );
  }

  Future<AdminModerationQueuePage> _listViaFallback({
    required AdminModerationCategory category,
    required AdminReportListFilter statusFilter,
    required AdminLookingForLifecycleFilter lfLifecycleFilter,
    required int page,
    required int pageSize,
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    final rows = <AdminModerationCaseRow>[];

    if (category != AdminModerationCategory.lookingFor) {
      final reports = await _review.listReports(
        filter: AdminReportListFilter.all,
        from: from,
        toExclusive: toExclusive,
      );
      for (final report in reports) {
        final orderLinked = isAdminOrderReport(
          category: report.category,
          orderId: report.orderId,
        );
        if (category == AdminModerationCategory.community && orderLinked) {
          continue;
        }
        if (category == AdminModerationCategory.order && !orderLinked) {
          continue;
        }
        rows.add(AdminModerationCaseRow.fromReport(report));
      }
    }

    if (category == AdminModerationCategory.all ||
        category == AdminModerationCategory.lookingFor) {
      try {
        final serverNow = await _lookingFor.serverNow();
        final lfReports = await _lookingFor.listReports();
        for (final report in lfReports) {
          if (from != null && report.createdAt.isBefore(from)) continue;
          if (toExclusive != null && !report.createdAt.isBefore(toExclusive)) {
            continue;
          }
          if (!_matchesLfLifecycleFilter(
            report,
            lfLifecycleFilter,
            serverNow,
          )) {
            continue;
          }
          rows.add(
            AdminModerationCaseRow.fromLookingFor(report, serverNow: serverNow),
          );
        }
      } catch (e) {
        debugPrint('AdminModerationQueueService looking-for fallback: $e');
      }
    }

    final seenCaseKeys = <String>{};
    final uniqueRows = <AdminModerationCaseRow>[];
    for (final row in rows) {
      final key = '${row.source}:${row.caseId}';
      if (seenCaseKeys.add(key)) {
        uniqueRows.add(row);
      }
    }

    final serverNow = DateTime.now().toUtc();
    final filtered =
        uniqueRows.where((row) {
          if (!_matchesStatusFilter(row, statusFilter)) return false;
          return _matchesSearch(row, search);
        }).toList()..sort((a, b) {
          if (category == AdminModerationCategory.lookingFor &&
              a.isLookingForReport &&
              b.isLookingForReport) {
            return compareLookingForReportPriority(
              reasonA: a.category,
              statusA: a.statusRaw,
              expiresA: a.lfExpiresAt,
              createdA: a.createdAt,
              openA: a.lfOpenReports ?? 1,
              violationsA: 0,
              reasonB: b.category,
              statusB: b.statusRaw,
              expiresB: b.lfExpiresAt,
              createdB: b.createdAt,
              openB: b.lfOpenReports ?? 1,
              violationsB: 0,
              serverNow: serverNow,
            );
          }
          return b.createdAt.compareTo(a.createdAt);
        });

    final offset = page * pageSize;
    final slice = offset >= filtered.length
        ? const <AdminModerationCaseRow>[]
        : filtered.sublist(
            offset,
            (offset + pageSize).clamp(0, filtered.length),
          );

    return AdminModerationQueuePage(items: slice, total: filtered.length);
  }

  static bool _matchesLfLifecycleFilter(
    LookingForAdminReport report,
    AdminLookingForLifecycleFilter filter,
    DateTime serverNow,
  ) {
    return switch (filter) {
      AdminLookingForLifecycleFilter.all => true,
      AdminLookingForLifecycleFilter.resolvedClosed =>
        report.status == 'resolved' || report.status == 'dismissed',
      AdminLookingForLifecycleFilter.activePost =>
        lookingForReportIsOpen(report.status) &&
            report.expiresAt != null &&
            report.expiresAt!.isAfter(serverNow),
      AdminLookingForLifecycleFilter.expiringSoon =>
        lookingForReportIsOpen(report.status) &&
            report.expiresAt != null &&
            report.expiresAt!.isAfter(serverNow) &&
            !report.expiresAt!.isAfter(
              serverNow.add(lookingForExpiringSoonWindow),
            ),
      AdminLookingForLifecycleFilter.expiredReviewRequired =>
        lookingForReportExpiredReviewRequired(
          status: report.status,
          expiresAt: report.expiresAt,
          serverNow: serverNow,
        ),
    };
  }

  static bool _matchesStatusFilter(
    AdminModerationCaseRow row,
    AdminReportListFilter filter,
  ) {
    if (filter == AdminReportListFilter.all) return true;
    final status = row.statusRaw;
    return switch (filter) {
      AdminReportListFilter.underReview => status == kAdminReportOpenStatus,
      AdminReportListFilter.needsMoreEvidence =>
        status == kAdminReportNeedsEvidenceStatus,
      AdminReportListFilter.resolved => status == 'resolved',
      AdminReportListFilter.dismissed => status == 'dismissed',
      AdminReportListFilter.all => true,
    };
  }

  static bool _matchesSearch(AdminModerationCaseRow row, String? search) {
    final term = search?.trim().toLowerCase();
    if (term == null || term.isEmpty) return true;
    final haystack = [
      row.summary,
      row.category,
      row.actorName,
      row.subjectName,
      row.orderNumber ?? '',
      row.caseId,
    ].join(' ').toLowerCase();
    return haystack.contains(term);
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
