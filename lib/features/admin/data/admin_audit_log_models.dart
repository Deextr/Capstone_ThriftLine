import 'admin_review_rules.dart';

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
    this.actorFullName,
    this.actorRole,
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
  final String? actorFullName;
  final String? actorRole;
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
      actorFullName: json['actor_full_name']?.toString(),
      actorRole: json['actor_role']?.toString(),
      targetType: json['target_type']?.toString(),
      targetId: json['target_id']?.toString(),
      details: details,
    );
  }

  String get displayEvent => _eventLabels[eventType] ?? titleCase(eventType);

  bool get isSystemAction =>
      (actorUserId == null || actorUserId!.trim().isEmpty) &&
      (actorFullName == null || actorFullName!.trim().isEmpty) &&
      (actorEmail == null || actorEmail!.trim().isEmpty);

  /// Role line for Activity Logs table (e.g. Superadmin, Admin, System).
  String get actorRoleDisplayLine {
    if (isSystemAction) return 'System';
    return switch (actorRole?.trim().toLowerCase()) {
      'super_admin' => 'Superadmin',
      'admin' => 'Admin',
      _ => 'Administrator',
    };
  }

  /// Name line shown under [actorRoleDisplayLine] in smaller text.
  String get actorNameDisplayLine {
    if (isSystemAction) return 'Automated system process';
    final name = actorFullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = actorEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Unknown administrator';
  }

  String get actorLabel {
    if (isSystemAction) return 'System';
    final name = actorFullName?.trim();
    final role = accountRoleLabel(actorRole);
    if (name != null && name.isNotEmpty) {
      return role == 'Member' ? name : '$name — $role';
    }
    return actorEmail ?? 'Administrator';
  }

  String get resultLabel => switch (status.trim().toLowerCase()) {
    'success' => 'Successful',
    'failed' => 'Failed',
    'blocked' => 'Blocked',
    _ => titleCase(status),
  };

  String get moduleLabel => AdminAuditCategory.labelFor(category);

  /// Primary target line for tables (never a raw UUID).
  String get targetDisplayPrimary {
    final fromDetails = _targetNameFromDetails();
    if (fromDetails != null) return fromDetails;

    final fromSummary = _targetNameFromSummary(summary);
    if (fromSummary != null) return fromSummary;

    final friendly = _targetTypeFriendlyLabel;
    if (friendly != null) return friendly;

    return '—';
  }

  /// Optional context: record type and/or compact reference.
  String? get targetDisplaySecondary {
    final primary = targetDisplayPrimary;
    final friendly = _targetTypeFriendlyLabel;
    final id = targetId?.trim();

    String? compactRef;
    if (id != null && id.isNotEmpty) {
      if (_looksLikeUuid(id)) {
        compactRef = 'Ref ${_shortUuid(id)}';
      } else if (id != primary) {
        compactRef = id;
      }
    }

    if (compactRef != null &&
        friendly != null &&
        primary != friendly &&
        primary != compactRef) {
      return compactRef;
    }
    if (compactRef != null && (friendly == null || primary == friendly)) {
      return compactRef;
    }
    if (friendly != null && primary != friendly) return friendly;
    return null;
  }

  String get targetLabel => targetDisplayPrimary;

  static bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  static String _shortUuid(String uuid) {
    final normalized = uuid.trim();
    if (normalized.length <= 8) return normalized.toUpperCase();
    return normalized.substring(normalized.length - 8).toUpperCase();
  }

  String? _targetNameFromDetails() {
    const keys = [
      'full_name',
      'shop_name',
      'target_name',
      'user_name',
      'email',
      'order_number',
      'order_reference',
      'applicant_name',
    ];
    for (final key in keys) {
      final raw = details[key];
      final value = raw?.toString().trim() ?? '';
      if (value.isEmpty || value == 'null') continue;
      if (_looksLikeUuid(value)) continue;
      return value;
    }
    return null;
  }

  static String? _targetNameFromSummary(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final disabled = RegExp(
      r'disabled marketplace account\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (disabled != null) {
      final name = disabled.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }

    final invited = RegExp(
      r'invited administrator\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (invited != null) {
      final name = invited.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }

    return null;
  }

  String? get _targetTypeFriendlyLabel {
    final type = targetType?.trim().toLowerCase();
    if (type == null || type.isEmpty) {
      return _targetTypeFromEvent;
    }
    return switch (type) {
      'user' => 'Marketplace user',
      'verification' => 'Seller verification',
      'report' => _reportTargetLabel,
      'looking_for_report' => 'Looking For report',
      'dispute' => 'Delivery dispute',
      'escrow' => 'Escrow payment',
      'admin_invitation' => 'Admin invitation',
      'order' => 'Order',
      _ => titleCase(type),
    };
  }

  String get _reportTargetLabel {
    final event = eventType.trim().toLowerCase();
    if (event.contains('order')) return 'Order dispute';
    return 'Community report';
  }

  String? get _targetTypeFromEvent {
    return switch (eventType.trim().toLowerCase()) {
      'seller_verification_approved' ||
      'seller_verification_rejected' => 'Seller verification',
      'marketplace_account_disabled' => 'Marketplace user',
      'report_decided' => 'Community report',
      'order_report_closed' ||
      'order_report_evidence_requested' => 'Order dispute',
      'looking_for_report_decided' => 'Looking For report',
      'delivery_dispute_closed' => 'Delivery dispute',
      'delivery_payment_released' ||
      'delivery_payment_refunded' => 'Escrow payment',
      'admin_invited' ||
      'admin_invitation_resent' ||
      'admin_invitation_revoked' ||
      'admin_invitation_accepted' => 'Admin invitation',
      'admin_activated' || 'admin_deactivated' => 'Administrator account',
      'super_admin_designated' => 'Super Admin account',
      _ => null,
    };
  }

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
  'order_report_evidence_requested': 'Evidence requested',
  'order_report_closed': 'Order report closed',
  'admin_invited': 'Admin invited',
  'admin_invitation_resent': 'Invitation resent',
  'admin_invitation_revoked': 'Invitation revoked',
  'admin_invitation_accepted': 'Invitation accepted',
  'admin_activated': 'Admin activated',
  'admin_deactivated': 'Admin deactivated',
  'super_admin_designated': 'Super Admin designated',
  'marketplace_account_disabled': 'Disabled user account',
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
    (value: all, label: 'All actions'),
    (value: accountManagement, label: 'Account management'),
    (value: sellerVerification, label: 'Seller verification'),
    (value: reportsDisputes, label: 'Disputes'),
    (value: paymentsEscrow, label: 'Orders & payments'),
    (value: systemSecurity, label: 'System events'),
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

abstract final class AdminAuditActorFilter {
  static const all = 'all';
  static const administrator = 'administrator';
  static const superAdmin = 'super_admin';
  static const system = 'system';

  static const filterOptions = <({String value, String label})>[
    (value: all, label: 'All actors'),
    (value: administrator, label: 'Administrators'),
    (value: superAdmin, label: 'Superadmins'),
    (value: system, label: 'System'),
  ];
}
