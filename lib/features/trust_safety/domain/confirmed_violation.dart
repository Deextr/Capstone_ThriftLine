/// A confirmed violation record returned by Supabase RPCs.
class ConfirmedViolationSummary {
  const ConfirmedViolationSummary({
    required this.source,
    required this.recordId,
    required this.category,
    required this.confirmedAt,
    required this.referenceTitle,
    required this.penaltyStatus,
    this.strikeNumber,
    this.violationNumber,
    this.consequence,
    this.reason,
    this.orderId,
    this.reportId,
    this.postId,
    this.sourceKind,
  });

  final String source;
  final String recordId;
  final String category;
  final DateTime confirmedAt;
  final String referenceTitle;
  final String penaltyStatus;
  final int? strikeNumber;
  final int? violationNumber;
  final String? consequence;
  final String? reason;
  final String? orderId;
  final String? reportId;
  final String? postId;
  final String? sourceKind;

  factory ConfirmedViolationSummary.fromMap(Map<String, dynamic> map) {
    DateTime parseTime(dynamic value) {
      if (value is DateTime) return value.toUtc();
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    int? parseInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    return ConfirmedViolationSummary(
      source: map['source']?.toString() ?? '',
      recordId: map['record_id']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      confirmedAt: parseTime(map['confirmed_at']),
      referenceTitle: map['reference_title']?.toString().trim().isNotEmpty == true
          ? map['reference_title'].toString().trim()
          : 'Violation',
      penaltyStatus: map['penalty_status']?.toString() ?? 'recorded',
      strikeNumber: parseInt(map['strike_number']),
      violationNumber: parseInt(map['violation_number']),
      consequence: map['consequence']?.toString(),
      reason: map['reason']?.toString(),
      orderId: map['order_id']?.toString(),
      reportId: map['report_id']?.toString(),
      postId: map['post_id']?.toString(),
      sourceKind: map['source_kind']?.toString(),
    );
  }

  String get routeKey => '$source/$recordId';
}

class ConfirmedViolationDetail {
  const ConfirmedViolationDetail({
    required this.summary,
    this.referenceDescription,
    this.adminExplanation,
    this.enforcementReason,
    this.resolutionFinancial,
    this.resolutionReturnRequired,
    this.restrictedUntil,
    this.permanentlyDisabledAt,
    this.disableReason,
    this.paymentDueAt,
    this.expiredAt,
    this.totalStrikes,
    this.totalViolations,
    this.canAppeal = false,
  });

  final ConfirmedViolationSummary summary;
  final String? referenceDescription;
  final String? adminExplanation;
  final String? enforcementReason;
  final String? resolutionFinancial;
  final bool? resolutionReturnRequired;
  final DateTime? restrictedUntil;
  final DateTime? permanentlyDisabledAt;
  final String? disableReason;
  final DateTime? paymentDueAt;
  final DateTime? expiredAt;
  final int? totalStrikes;
  final int? totalViolations;
  final bool canAppeal;

  factory ConfirmedViolationDetail.fromMap(Map<String, dynamic> map) {
    DateTime? parseOpt(dynamic value) {
      if (value is DateTime) return value.toUtc();
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toUtc();
      }
      return null;
    }

    int? parseInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final summary = ConfirmedViolationSummary.fromMap(map);
    return ConfirmedViolationDetail(
      summary: summary,
      referenceDescription: map['reference_description']?.toString(),
      adminExplanation: map['admin_explanation']?.toString(),
      enforcementReason: map['enforcement_reason']?.toString(),
      resolutionFinancial: map['resolution_financial']?.toString(),
      resolutionReturnRequired: map['resolution_return_required'] == true,
      restrictedUntil: parseOpt(map['restricted_until']),
      permanentlyDisabledAt: parseOpt(map['permanently_disabled_at']),
      disableReason: map['disable_reason']?.toString(),
      paymentDueAt: parseOpt(map['payment_due_at']),
      expiredAt: parseOpt(map['expired_at']),
      totalStrikes: parseInt(map['total_strikes']),
      totalViolations: parseInt(map['total_violations']),
      canAppeal: map['can_appeal'] == true,
    );
  }
}
