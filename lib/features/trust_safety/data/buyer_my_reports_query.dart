import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/buyer_looking_for_report_model.dart';
import '../../../models/community_report_model.dart';
import '../../buyer/data/order_query.dart';
import '../../buyer/domain/looking_for_lifecycle.dart';
import '../domain/buyer_report_list_item.dart';
import 'buyer_report_filters.dart';
import 'report_reasons.dart';

/// Reports shown per page on Buyer → My Reports.
const int kBuyerMyReportsPageSize = 5;

List<T> paginateList<T>(
  List<T> items, {
  required int pageIndex,
  int pageSize = kBuyerMyReportsPageSize,
}) {
  if (items.isEmpty || pageSize <= 0) return const [];
  final totalPages = (items.length / pageSize).ceil();
  final safePage = pageIndex.clamp(0, totalPages - 1);
  final start = safePage * pageSize;
  final end = start + pageSize;
  if (start >= items.length) return const [];
  return items.sublist(start, end > items.length ? items.length : end);
}

int buyerMyReportsTotalPages(
  int itemCount, {
  int pageSize = kBuyerMyReportsPageSize,
}) {
  if (itemCount <= 0 || pageSize <= 0) return 0;
  return (itemCount / pageSize).ceil();
}

@visibleForTesting
List<BuyerReportListItem> mergeAndSortBuyerReportItems(
  Iterable<BuyerReportListItem> items,
) {
  final list = items.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
}

class BuyerMyReportsLoadResult {
  const BuyerMyReportsLoadResult({
    required this.items,
    required this.communityReports,
  });

  final List<BuyerReportListItem> items;
  final List<CommunityReportModel> communityReports;
}

Future<BuyerMyReportsLoadResult> fetchBuyerMyReports(
  SupabaseService supabase,
  String reporterId,
) async {
  if (reporterId.isEmpty) {
    return const BuyerMyReportsLoadResult(items: [], communityReports: []);
  }

  final communityRows = await _fetchCommunityReportRows(supabase, reporterId);
  final lookingForRows = await _fetchLookingForReportRows(supabase, reporterId);

  final items = mergeAndSortBuyerReportItems([
    ...communityRows.map(_listItemFromCommunity),
    ...lookingForRows.map(_listItemFromLookingFor),
  ]);
  return BuyerMyReportsLoadResult(
    items: items,
    communityReports: communityRows,
  );
}

Future<BuyerLookingForReportModel?> fetchBuyerLookingForReportById(
  SupabaseService supabase,
  String reporterId,
  String reportId,
) async {
  if (reporterId.isEmpty || reportId.isEmpty) return null;

  final row = await supabase.client
      .from('looking_for_reports')
      .select(
        'report_id, post_id, reporter_id, reported_user_id, reason, details, '
        'status, created_at, resolved_at, reporter_instruction, '
        'evidence_attempt_count, decision_outcome, snapshot_title, '
        'snapshot_description, snapshot_image_path, '
        'looking_for_posts ( title, description, reference_image_url )',
      )
      .eq('report_id', reportId)
      .eq('reporter_id', reporterId)
      .maybeSingle();
  if (row == null) return null;

  final reportedId = row['reported_user_id'] as String?;
  final profiles = reportedId == null
      ? <String, Map<String, dynamic>>{}
      : await loadPublicProfiles(supabase, {reportedId});

  final evidenceRows = await supabase.client
      .from('looking_for_report_evidence')
      .select('evidence_id, file_path, created_at')
      .eq('report_id', reportId)
      .order('created_at', ascending: true);

  final evidence = (evidenceRows as List<dynamic>)
      .map(
        (item) => ReportEvidenceItem.fromSupabase(item as Map<String, dynamic>),
      )
      .toList();

  var report = BuyerLookingForReportModel.fromSupabase(
    row,
    reportedUser: reportedId == null ? null : profiles[reportedId],
    evidence: evidence,
  );
  report = await _withLookingForEvidenceSignedUrls(supabase, report);
  return report;
}

Future<List<CommunityReportModel>> _fetchCommunityReportRows(
  SupabaseService supabase,
  String reporterId,
) async {
  final rows = await supabase.client
      .from('reports')
      .select(
        'report_id, reporter_id, reported_user_id, order_id, category, details, '
        'status, created_at, resolved_at',
      )
      .eq('reporter_id', reporterId)
      .order('created_at', ascending: false);

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

  final profiles = await loadPublicProfiles(supabase, userIds);
  final orderNumbers = await _loadOrderNumbers(supabase, orderIds);

  return raw.map((row) {
    final reportedId = row['reported_user_id'] as String?;
    final orderId = row['order_id'] as String?;
    return CommunityReportModel.fromSupabase(
      row,
      reportedUser: reportedId == null ? null : profiles[reportedId],
      orderNumber: orderId == null ? null : orderNumbers[orderId],
    );
  }).toList();
}

Future<List<BuyerLookingForReportModel>> _fetchLookingForReportRows(
  SupabaseService supabase,
  String reporterId,
) async {
  final rows = await supabase.client
      .from('looking_for_reports')
      .select(
        'report_id, post_id, reporter_id, reported_user_id, reason, details, '
        'status, created_at, resolved_at, snapshot_title, '
        'looking_for_posts ( title )',
      )
      .eq('reporter_id', reporterId)
      .order('created_at', ascending: false);

  final raw = (rows as List<dynamic>)
      .map((row) => row as Map<String, dynamic>)
      .toList();

  final userIds = raw
      .map((row) => row['reported_user_id'] as String?)
      .whereType<String>()
      .toSet();
  final profiles = await loadPublicProfiles(supabase, userIds);

  return raw.map((row) {
    final reportedId = row['reported_user_id'] as String?;
    return BuyerLookingForReportModel.fromSupabase(
      row,
      reportedUser: reportedId == null ? null : profiles[reportedId],
    );
  }).toList();
}

BuyerReportListItem _listItemFromCommunity(CommunityReportModel report) {
  final kind = buyerReportKindFromCommunityRow(
    category: report.category,
    orderId: report.orderId,
  );
  final subject = switch (kind) {
    BuyerReportTypeFilter.order =>
      report.orderNumber != null && report.orderNumber!.isNotEmpty
          ? 'Order ${report.orderNumber}'
          : 'Order report',
    _ =>
      report.reportedUsername.isNotEmpty
          ? '@${report.reportedUsername}'
          : report.reportedDisplayName,
  };
  return BuyerReportListItem(
    id: report.id,
    kind: kind,
    status: report.status,
    reasonLabel: reportReasonLabel(report.category),
    subjectLabel: subject,
    createdAt: report.createdAt,
  );
}

BuyerReportListItem _listItemFromLookingFor(BuyerLookingForReportModel report) {
  final title = report.displayPostTitle;
  final subject = title.isNotEmpty
      ? title
      : (report.reportedUsername.isNotEmpty
            ? '@${report.reportedUsername}'
            : report.reportedDisplayName);
  return BuyerReportListItem(
    id: report.id,
    kind: BuyerReportTypeFilter.lookingFor,
    status: report.status,
    reasonLabel: lookingForReportReasonLabel(report.reason) ?? report.reason,
    subjectLabel: subject,
    createdAt: report.createdAt,
  );
}

Future<Map<String, String>> _loadOrderNumbers(
  SupabaseService supabase,
  Set<String> ids,
) async {
  if (ids.isEmpty) return {};
  try {
    final rows = await supabase.client
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
    debugPrint('buyer_my_reports_query order numbers error: $e');
    return {};
  }
}

Future<BuyerLookingForReportModel> _withLookingForEvidenceSignedUrls(
  SupabaseService supabase,
  BuyerLookingForReportModel report,
) async {
  if (report.evidence.isEmpty) return report;
  const buckets = ['report-evidence', 'looking-for'];
  final signed = <ReportEvidenceItem>[];
  for (final item in report.evidence) {
    String? url;
    for (final bucket in buckets) {
      try {
        url = await supabase.client.storage
            .from(bucket)
            .createSignedUrl(item.filePath, 3600);
        if (url.isNotEmpty) break;
      } catch (_) {}
    }
    signed.add(item.copyWith(signedUrl: url));
  }
  return report.copyWith(evidence: signed);
}
