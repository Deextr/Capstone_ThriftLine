class AdminAuditLogRow {
  const AdminAuditLogRow({
    required this.logId,
    required this.createdAt,
    required this.category,
    required this.eventType,
    required this.status,
    required this.summary,
    this.actorUserId,
    this.actorEmail,
    this.targetType,
    this.targetId,
    this.details = const {},
  });

  final String logId;
  final DateTime createdAt;
  final String category;
  final String eventType;
  final String status;
  final String summary;
  final String? actorUserId;
  final String? actorEmail;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> details;

  factory AdminAuditLogRow.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? raw) {
      if (raw is DateTime) return raw.toUtc();
      return DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    Map<String, dynamic> details = const {};
    final d = json['details'];
    if (d is Map) {
      details = Map<String, dynamic>.from(d);
    }

    return AdminAuditLogRow(
      logId: json['log_id']?.toString() ?? '',
      createdAt: parseTime(json['created_at']),
      category: json['category']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      actorUserId: json['actor_user_id']?.toString(),
      actorEmail: json['actor_email']?.toString(),
      targetType: json['target_type']?.toString(),
      targetId: json['target_id']?.toString(),
      details: details,
    );
  }

  String get displayEvent => _eventLabels[eventType] ?? titleCase(eventType);

  static String titleCase(String raw) {
    return raw
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }
}

const _eventLabels = <String, String>{
  'admin_login_completed': 'Successful login',
  'admin_login_password_accepted': 'Credentials accepted',
  'admin_login_failed': 'Failed login',
  'admin_login_lockout': 'Login lockout',
  'admin_login_blocked': 'Login blocked (lockout)',
  'admin_login_denied': 'Login denied',
  'admin_turnstile_failed': 'Turnstile failed',
  'admin_logout': 'Admin logout',
  'seller_verification_approved': 'Seller approved',
  'seller_verification_rejected': 'Seller rejected',
  'report_decided': 'Report decision',
  'delivery_dispute_closed': 'Dispute closed',
  'delivery_payment_released': 'Escrow released',
  'delivery_payment_refunded': 'Refund approved',
  'looking_for_report_decided': 'Looking-for report',
};

abstract final class AdminAuditCategory {
  static const all = 'all';
  static const authentication = 'authentication';
  static const sellerVerification = 'seller_verification';
  static const reportsDisputes = 'reports_disputes';
  static const accountManagement = 'account_management';
  static const paymentsEscrow = 'payments_escrow';
  static const systemSecurity = 'system_security';

  static const filterOptions = <({String value, String label})>[
    (value: all, label: 'All'),
    (value: authentication, label: 'Authentication'),
    (value: sellerVerification, label: 'Seller verification'),
    (value: reportsDisputes, label: 'Reports / disputes'),
    (value: accountManagement, label: 'Account management'),
    (value: paymentsEscrow, label: 'Payments / escrow'),
    (value: systemSecurity, label: 'System / security'),
  ];

  static String labelFor(String value) {
    for (final opt in filterOptions) {
      if (opt.value == value) return opt.label;
    }
    return AdminAuditLogRow.titleCase(value);
  }
}

abstract final class AdminAuditStatusFilter {
  static const all = 'all';
  static const success = 'success';
  static const failed = 'failed';
  static const blocked = 'blocked';
}
