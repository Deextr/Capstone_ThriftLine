import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/community_report_model.dart';
import '../../../models/order_model.dart';
import '../../buyer/data/order_query.dart';
import '../../../models/enums.dart';
import '../../trust_safety/data/report_reasons.dart';
import 'admin_delivery_dispute.dart';
import 'admin_review_rules.dart';
import 'delivery_payment_hold.dart';
import 'delivery_payment_resolve.dart';

class AdminReviewCounts {
  const AdminReviewCounts({
    required this.sellerApplications,
    required this.communityReports,
    required this.deliveryProblems,
  });

  final int sellerApplications;
  final int communityReports;
  final int deliveryProblems;
}

enum AdminActivityTarget { application, report, dispute }

class AdminReviewActivity {
  const AdminReviewActivity({
    required this.title,
    required this.detail,
    required this.occurredAt,
    required this.target,
    required this.id,
  });

  final String title;
  final String detail;
  final DateTime occurredAt;
  final AdminActivityTarget target;
  final String id;
}

class AdminReviewService {
  AdminReviewService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminReviewCounts> loadQueueCounts() async {
    final results = await Future.wait([
      _countRows(
        'user_verifications',
        column: 'verification_status',
        equals: 'pending',
      ),
      _countRows('reports', column: 'status', equals: kAdminReportOpenStatus),
      _countRows(
        'delivery_disputes',
        column: 'status',
        equals: kAdminDisputeOpenStatus,
      ),
    ]);
    return AdminReviewCounts(
      sellerApplications: results[0],
      communityReports: results[1],
      deliveryProblems: results[2],
    );
  }

  /// Latest real decisions the admin can already read. A failed source is
  /// skipped so the review queues still load.
  Future<List<AdminReviewActivity>> loadRecentActivity() async {
    final batches = await Future.wait([
      _recentApplications(),
      _recentReports(),
      _recentDisputes(),
    ]);
    final items = batches.expand((batch) => batch).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (items.length <= 5) return items;
    return items.sublist(0, 5);
  }

  Future<List<AdminReviewActivity>> _recentApplications() async {
    try {
      final rows = await _supabase.client
          .from('user_verifications')
          .select(
            'verification_id, shop_name, verification_status, reviewed_at',
          )
          .inFilter('verification_status', ['approved', 'rejected'])
          .order('reviewed_at', ascending: false)
          .limit(5);
      return [
        for (final row in rows as List)
          if (row is Map<String, dynamic>)
            if (_activityTime(row['reviewed_at']) case final at?)
              if ((row['verification_id'] as String?)?.isNotEmpty == true)
                AdminReviewActivity(
                  title: adminApplicationActivityTitle(
                    row['verification_status'] as String? ?? '',
                  ),
                  detail: (row['shop_name'] as String?)?.trim() ?? '',
                  occurredAt: at,
                  target: AdminActivityTarget.application,
                  id: row['verification_id'] as String,
                ),
      ];
    } catch (e) {
      debugPrint('AdminReviewService recent applications error: $e');
      return const [];
    }
  }

  Future<List<AdminReviewActivity>> _recentReports() async {
    try {
      final rows = await _supabase.client
          .from('reports')
          .select('report_id, category, status, resolved_at')
          .inFilter('status', kAdminReportClosedStatuses)
          .order('resolved_at', ascending: false)
          .limit(5);
      return [
        for (final row in rows as List)
          if (row is Map<String, dynamic>)
            if (_activityTime(row['resolved_at']) case final at?)
              if ((row['report_id'] as String?)?.isNotEmpty == true)
                AdminReviewActivity(
                  title: adminReportActivityTitle(
                    row['status'] as String? ?? '',
                  ),
                  detail: reportReasonLabel(row['category'] as String? ?? ''),
                  occurredAt: at,
                  target: AdminActivityTarget.report,
                  id: row['report_id'] as String,
                ),
      ];
    } catch (e) {
      debugPrint('AdminReviewService recent reports error: $e');
      return const [];
    }
  }

  Future<List<AdminReviewActivity>> _recentDisputes() async {
    try {
      final rows = await _supabase.client
          .from('delivery_disputes')
          .select('dispute_id, reason, resolved_at')
          .eq('status', kAdminDisputeClosedStatus)
          .order('resolved_at', ascending: false)
          .limit(5);
      return [
        for (final row in rows as List)
          if (row is Map<String, dynamic>)
            if (_activityTime(row['resolved_at']) case final at?)
              if ((row['dispute_id'] as String?)?.isNotEmpty == true)
                AdminReviewActivity(
                  title: 'Delivery case closed',
                  detail: DeliveryDisputeReason.fromDb(
                    row['reason'] as String?,
                  ).label,
                  occurredAt: at,
                  target: AdminActivityTarget.dispute,
                  id: row['dispute_id'] as String,
                ),
      ];
    } catch (e) {
      debugPrint('AdminReviewService recent disputes error: $e');
      return const [];
    }
  }

  DateTime? _activityTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<int> _countRows(
    String table, {
    required String column,
    required String equals,
  }) async {
    final rows = await _supabase.client
        .from(table)
        .select(column)
        .eq(column, equals);
    return (rows as List).length;
  }

  Future<List<CommunityReportModel>> listReports({
    required AdminQueueFilter filter,
  }) async {
    var query = _supabase.client
        .from('reports')
        .select(
          '*, report_evidence(report_evidence_id, file_path, created_at)',
        );
    if (filter == AdminQueueFilter.open) {
      query = query.eq('status', kAdminReportOpenStatus);
    } else {
      query = query.inFilter('status', kAdminReportClosedStatuses);
    }
    final rows = await query.order(
      'created_at',
      ascending: filter == AdminQueueFilter.open,
    );
    return _mapReports(
      (rows as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList(),
    );
  }

  Future<CommunityReportModel?> getReport(String reportId) async {
    final row = await _supabase.client
        .from('reports')
        .select('*, report_evidence(report_evidence_id, file_path, created_at)')
        .eq('report_id', reportId)
        .maybeSingle();
    if (row == null) return null;
    final mapped = await _mapReports([row]);
    if (mapped.isEmpty) return null;
    return _withSignedUrls(mapped.first);
  }

  Future<List<AdminDeliveryDispute>> listDisputes({
    required AdminQueueFilter filter,
  }) async {
    var query = _supabase.client.from('delivery_disputes').select();
    if (filter == AdminQueueFilter.open) {
      query = query.eq('status', kAdminDisputeOpenStatus);
    } else {
      query = query.eq('status', kAdminDisputeClosedStatus);
    }
    final rows = await query.order(
      'created_at',
      ascending: filter == AdminQueueFilter.open,
    );
    return _mapDisputes(
      (rows as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList(),
      hydrateOrders: true,
    );
  }

  Future<AdminDeliveryDispute?> getDispute(String disputeId) async {
    final row = await _supabase.client
        .from('delivery_disputes')
        .select()
        .eq('dispute_id', disputeId)
        .maybeSingle();
    if (row == null) return null;
    final mapped = await _mapDisputes([row], hydrateOrders: true);
    if (mapped.isEmpty) return null;
    return mapped.first.copyWith(
      paymentHold: await _loadPaymentHold(mapped.first.orderId),
    );
  }

  Future<String?> decideReport({
    required String reportId,
    required String decision,
    required String adminResponse,
  }) async {
    try {
      final rpcRes = await _supabase.client.rpc(
        'decide_report',
        params: {
          'p_report_id': reportId,
          'p_decision': decision,
          'p_admin_response': adminResponse.trim(),
        },
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not save that decision.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('decide_report error: $e');
      return adminFriendlyError(e, 'Could not save that decision.');
    }
  }

  Future<String?> closeDeliveryDispute({
    required String disputeId,
    String? adminNote,
  }) async {
    try {
      final rpcRes = await _supabase.client.rpc(
        'close_delivery_dispute',
        params: {'p_dispute_id': disputeId, 'p_admin_note': adminNote?.trim()},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not close this delivery problem.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('close_delivery_dispute error: $e');
      return adminFriendlyError(e, 'Could not close this delivery problem.');
    }
  }

  Future<DeliveryPaymentHold?> _loadPaymentHold(String orderId) async {
    if (orderId.isEmpty) return null;
    try {
      final row = await _supabase.client
          .from('escrow')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();
      if (row == null) return null;
      return DeliveryPaymentHold.fromSupabase(row);
    } catch (e) {
      debugPrint('AdminReviewService escrow error: $e');
      return null;
    }
  }

  Future<DeliveryPaymentResult> releaseDeliveryPayment({
    required String disputeId,
    String? adminNote,
  }) {
    return resolveDeliveryRelease(
      _supabase,
      disputeId: disputeId,
      adminNote: adminNote,
    );
  }

  Future<DeliveryPaymentResult> refundDeliveryPayment({
    required String disputeId,
    String? adminNote,
    required bool returnRequired,
  }) {
    return resolveDeliveryRefund(
      _supabase,
      disputeId: disputeId,
      adminNote: adminNote,
      returnRequired: returnRequired,
    );
  }

  Future<String?> cancelItemReturn(String disputeId) async {
    try {
      final rpcRes = await _supabase.client.rpc(
        'cancel_return_shipment',
        params: {'p_dispute_id': disputeId},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not stop this return.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('cancel_return_shipment error: $e');
      return 'Could not stop this return.';
    }
  }

  Future<List<CommunityReportModel>> _mapReports(
    List<Map<String, dynamic>> raw,
  ) async {
    if (raw.isEmpty) return const [];

    final userIds = <String>{};
    final orderIds = <String>{};
    for (final row in raw) {
      final reporterId = row['reporter_id'] as String?;
      final reportedId = row['reported_user_id'] as String?;
      final orderId = row['order_id'] as String?;
      if (reporterId != null) userIds.add(reporterId);
      if (reportedId != null) userIds.add(reportedId);
      if (orderId != null) orderIds.add(orderId);
    }

    final profiles = await loadPublicProfiles(_supabase, userIds);
    final orders = await _loadOrders(orderIds);

    return raw.map((row) {
      final evidenceRows =
          (row['report_evidence'] as List<dynamic>? ?? const [])
              .map(
                (item) => ReportEvidenceItem.fromSupabase(
                  item as Map<String, dynamic>,
                ),
              )
              .toList();
      final reportedId = row['reported_user_id'] as String?;
      final reporterId = row['reporter_id'] as String?;
      final orderId = row['order_id'] as String?;
      final order = orderId == null ? null : orders[orderId];
      return CommunityReportModel.fromSupabase(
        row,
        reportedUser: reportedId == null ? null : profiles[reportedId],
        reporterUser: reporterId == null ? null : profiles[reporterId],
        orderNumber: order?.orderNumber,
        orderTitle: order?.productTitle,
        evidence: evidenceRows,
      );
    }).toList();
  }

  Future<List<AdminDeliveryDispute>> _mapDisputes(
    List<Map<String, dynamic>> raw, {
    required bool hydrateOrders,
  }) async {
    if (raw.isEmpty) return const [];

    final orderIds = raw
        .map((row) => row['order_id'] as String?)
        .whereType<String>()
        .toSet();
    final orders = hydrateOrders
        ? await _loadOrders(orderIds)
        : <String, OrderModel>{};

    final userIds = <String>{};
    for (final row in raw) {
      final buyerId = row['buyer_id'] as String?;
      if (buyerId != null) userIds.add(buyerId);
      final order = orders[row['order_id'] as String?];
      if (order != null) {
        userIds.add(order.buyerId);
        userIds.add(order.sellerId);
      }
    }
    final profiles = await loadPublicProfiles(_supabase, userIds);

    return raw.map((row) {
      final order = orders[row['order_id'] as String?];
      final buyerId = row['buyer_id'] as String? ?? order?.buyerId;
      final sellerId = order?.sellerId;
      return AdminDeliveryDispute.fromSupabase(
        row,
        order: order,
        buyer: buyerId == null ? null : profiles[buyerId],
        seller: sellerId == null ? null : profiles[sellerId],
      );
    }).toList();
  }

  Future<Map<String, OrderModel>> _loadOrders(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase.client
          .from('orders')
          .select(kOrderSelect)
          .inFilter('order_id', ids.toList());
      final orders = await hydrateOrders(
        _supabase,
        (rows as List<dynamic>)
            .map((row) => row as Map<String, dynamic>)
            .toList(),
      );
      return {for (final order in orders) order.id: order};
    } catch (e) {
      debugPrint('AdminReviewService orders error: $e');
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
            .from(kAdminEvidenceBucket)
            .createSignedUrl(item.filePath, kAdminSignedUrlSeconds);
        signed.add(item.copyWith(signedUrl: url));
      } catch (e) {
        debugPrint('admin report evidence signed URL error: $e');
        signed.add(item);
      }
    }
    return report.copyWith(evidence: signed);
  }
}
