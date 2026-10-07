import '../core/utils/report_status.dart';
import 'base_model.dart';

class ReportEvidenceItem {
  const ReportEvidenceItem({
    required this.id,
    required this.filePath,
    this.signedUrl,
    required this.createdAt,
  });

  final String id;
  final String filePath;
  final String? signedUrl;
  final DateTime createdAt;

  factory ReportEvidenceItem.fromSupabase(Map<String, dynamic> row) {
    return ReportEvidenceItem(
      id: row['report_evidence_id'] as String? ?? '',
      filePath: row['file_path'] as String? ?? '',
      signedUrl: row['signed_url'] as String?,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ReportEvidenceItem copyWith({String? signedUrl}) {
    return ReportEvidenceItem(
      id: id,
      filePath: filePath,
      signedUrl: signedUrl ?? this.signedUrl,
      createdAt: createdAt,
    );
  }
}

class CommunityReportModel extends BaseModel {
  const CommunityReportModel({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.reportedUsername,
    required this.reportedDisplayName,
    this.reporterUsername = '',
    this.reporterDisplayName = '',
    this.reportedRole,
    this.reporterRole,
    this.reportedShopName,
    this.orderId,
    this.orderNumber,
    this.orderTitle,
    required this.category,
    required this.details,
    required this.status,
    this.adminResponse,
    this.reviewedBy,
    required this.createdAt,
    this.resolvedAt,
    this.evidence = const [],
    this.evidenceAttemptCount = 1,
    this.reporterInstruction,
    this.productId,
    this.disputeId,
    this.resolutionFinancial,
    this.resolutionReturnRequired,
  });

  final String id;
  final String reporterId;
  final String reportedUserId;
  final String reportedUsername;
  final String reportedDisplayName;
  final String reporterUsername;
  final String reporterDisplayName;
  final String? reportedRole;
  final String? reporterRole;
  final String? reportedShopName;
  final String? orderId;
  final String? orderNumber;
  final String? orderTitle;
  final String category;
  final String details;
  final String status;
  final String? adminResponse;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<ReportEvidenceItem> evidence;
  final int evidenceAttemptCount;
  final String? reporterInstruction;
  final String? productId;
  final String? disputeId;
  final String? resolutionFinancial;
  final bool? resolutionReturnRequired;

  factory CommunityReportModel.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? reportedUser,
    Map<String, dynamic>? reporterUser,
    String? orderNumber,
    String? orderTitle,
    List<ReportEvidenceItem> evidence = const [],
  }) {
    final user =
        (reportedUser ?? row['reported_user'] ?? row['user_public_profiles'])
            as Map<String, dynamic>?;
    final reporter =
        (reporterUser ?? row['reporter'] ?? row['reporter_profile'])
            as Map<String, dynamic>?;
    final username = user?['username'] as String? ?? '';
    final display =
        user?['full_name'] as String? ??
        (username.isNotEmpty ? username : 'Member');
    final reporterName = reporter?['username'] as String? ?? '';
    final reporterDisplay =
        reporter?['full_name'] as String? ??
        (reporterName.isNotEmpty ? reporterName : 'Member');

    DateTime? parseTime(Object? value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return CommunityReportModel(
      id: row['report_id'] as String? ?? '',
      reporterId: row['reporter_id'] as String? ?? '',
      reportedUserId: row['reported_user_id'] as String? ?? '',
      reportedUsername: username,
      reportedDisplayName: display,
      reporterUsername: reporterName,
      reporterDisplayName: reporterDisplay,
      reportedRole: user?['role'] as String?,
      reporterRole: reporter?['role'] as String?,
      reportedShopName: user?['shop_name'] as String?,
      orderId: row['order_id'] as String?,
      orderNumber: orderNumber ?? row['order_number'] as String?,
      orderTitle: orderTitle ?? row['order_title'] as String?,
      category: row['category'] as String? ?? 'other',
      details: row['details'] as String? ?? '',
      status: reportStatusFromDb(row['status']),
      adminResponse: row['admin_response'] as String?,
      reviewedBy: row['reviewed_by'] as String?,
      createdAt: parseTime(row['created_at']) ?? DateTime.now(),
      resolvedAt: parseTime(row['resolved_at']),
      evidence: evidence,
      evidenceAttemptCount: (row['evidence_attempt_count'] as num?)?.toInt() ?? 1,
      reporterInstruction: row['reporter_instruction'] as String?,
      productId: row['product_id'] as String?,
      disputeId: row['dispute_id'] as String?,
      resolutionFinancial: row['resolution_financial'] as String?,
      resolutionReturnRequired: row['resolution_return_required'] as bool?,
    );
  }

  CommunityReportModel copyWith({
    List<ReportEvidenceItem>? evidence,
    String? orderNumber,
    String? orderTitle,
    String? status,
    String? adminResponse,
    DateTime? resolvedAt,
    String? reporterUsername,
    String? reporterDisplayName,
    String? reportedRole,
    String? reporterRole,
    String? reportedShopName,
    String? reviewedBy,
  }) {
    return CommunityReportModel(
      id: id,
      reporterId: reporterId,
      reportedUserId: reportedUserId,
      reportedUsername: reportedUsername,
      reportedDisplayName: reportedDisplayName,
      reporterUsername: reporterUsername ?? this.reporterUsername,
      reporterDisplayName: reporterDisplayName ?? this.reporterDisplayName,
      reportedRole: reportedRole ?? this.reportedRole,
      reporterRole: reporterRole ?? this.reporterRole,
      reportedShopName: reportedShopName ?? this.reportedShopName,
      orderId: orderId,
      orderNumber: orderNumber ?? this.orderNumber,
      orderTitle: orderTitle ?? this.orderTitle,
      category: category,
      details: details,
      status: status ?? this.status,
      adminResponse: adminResponse ?? this.adminResponse,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      createdAt: createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      evidence: evidence ?? this.evidence,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'report_id': id,
    'reporter_id': reporterId,
    'reported_user_id': reportedUserId,
    'reported_username': reportedUsername,
    'category': category,
    'details': details,
    'status': status,
    'admin_response': adminResponse,
    'order_id': orderId,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommunityReportModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
