import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/community_report_model.dart';

const _reportSelectForOrder =
    'report_id, reporter_id, reported_user_id, order_id, category, details, '
    'status, admin_response, reviewed_by, created_at, resolved_at';

/// Keeps the newest report per [order_id] for buyer order views.
@visibleForTesting
Map<String, CommunityReportModel> pickLatestReportPerOrder(
  Iterable<CommunityReportModel> reports,
) {
  final out = <String, CommunityReportModel>{};
  for (final report in reports) {
    final orderId = report.orderId;
    if (orderId == null || orderId.isEmpty) continue;
    final existing = out[orderId];
    if (existing == null || report.createdAt.isAfter(existing.createdAt)) {
      out[orderId] = report;
    }
  }
  return out;
}

Future<Map<String, CommunityReportModel>> fetchMyReportsForOrders(
  SupabaseService supabase,
  String reporterId,
  Iterable<String> orderIds,
) async {
  final ids = orderIds.where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty || reporterId.isEmpty) return {};

  try {
    final rows = await supabase.client
        .from('reports')
        .select(_reportSelectForOrder)
        .eq('reporter_id', reporterId)
        .inFilter('order_id', ids)
        .order('created_at', ascending: false);

    final mapped = <CommunityReportModel>[];
    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      mapped.add(CommunityReportModel.fromSupabase(row));
    }
    return pickLatestReportPerOrder(mapped);
  } catch (e) {
    debugPrint('fetchMyReportsForOrders error: $e');
    return {};
  }
}
