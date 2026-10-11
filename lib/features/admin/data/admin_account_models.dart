class AdminAccountRecord {
  const AdminAccountRecord({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.accountStatus,
    required this.displayStatus,
    required this.createdAt,
    this.lastSignInAt,
    this.invitationId,
    this.invitationStatus,
    this.deactivatedAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final String role;
  final String accountStatus;
  final String displayStatus;
  final DateTime createdAt;
  final DateTime? lastSignInAt;
  final String? invitationId;
  final String? invitationStatus;
  final DateTime? deactivatedAt;

  bool get isSuperAdmin => role == 'super_admin';

  bool get canDeactivate =>
      !isSuperAdmin && displayStatus == 'active' && userId.isNotEmpty;

  bool get canActivate => !isSuperAdmin && displayStatus == 'inactive';

  bool get canResendInvite =>
      invitationId != null &&
      (invitationStatus == 'pending' || invitationStatus == 'expired') &&
      displayStatus == 'invited';

  bool get canRevokeInvite => canResendInvite;

  String get roleLabel => role == 'super_admin' ? 'Super Admin' : 'Admin';

  String get statusLabel => switch (displayStatus) {
    'active' => 'Active',
    'inactive' => 'Inactive',
    'invited' => 'Invited',
    _ => displayStatus,
  };

  factory AdminAccountRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(Object? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString())?.toLocal();
    }

    return AdminAccountRecord(
      userId: json['user_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'admin',
      accountStatus: json['account_status']?.toString() ?? 'active',
      displayStatus: json['display_status']?.toString() ?? 'active',
      createdAt: parseTime(json['created_at']) ?? DateTime.now(),
      lastSignInAt: parseTime(json['last_sign_in_at']),
      invitationId: json['invitation_id']?.toString(),
      invitationStatus: json['invitation_status']?.toString(),
      deactivatedAt: parseTime(json['deactivated_at']),
    );
  }
}

class AdminAccountCounts {
  const AdminAccountCounts({
    required this.total,
    required this.active,
    required this.inactive,
    required this.pending,
  });

  final int total;
  final int active;
  final int inactive;
  final int pending;

  static const empty = AdminAccountCounts(
    total: 0,
    active: 0,
    inactive: 0,
    pending: 0,
  );

  factory AdminAccountCounts.fromJson(Map<String, dynamic>? json) {
    int read(String key) {
      final value = json?[key];
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return AdminAccountCounts(
      total: read('total'),
      active: read('active'),
      inactive: read('inactive'),
      pending: read('pending'),
    );
  }
}

class AdminAccountPage {
  const AdminAccountPage({
    required this.rows,
    required this.total,
    required this.counts,
  });

  final List<AdminAccountRecord> rows;
  final int total;
  final AdminAccountCounts counts;
}

class AdminInviteResult {
  const AdminInviteResult({
    required this.ok,
    this.message,
    this.code,
    this.invitationId,
  });

  final bool ok;
  final String? message;
  final String? code;
  final String? invitationId;

  bool get canResend => code == 'invitation_pending' && invitationId != null;
}

const adminInviteBuyerOrSellerMessage =
    'This email address is already registered in ThriftLine. Please use a different email address to create an administrator account.';

const adminInviteExistingAccountMessage =
    'This email address is already associated with an existing ThriftLine account.';

const adminInvitePendingMessage =
    'An invitation has already been sent to this email address.';

String normalizeAdminEmail(String raw) => raw.trim().toLowerCase();

bool isAdminInviteEmail(String value) {
  if (value.isEmpty || value.length > 320) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}

String adminInviteFailureMessage({String? code, String? serverMessage}) {
  switch (code) {
    case 'buyer_or_seller':
      return adminInviteBuyerOrSellerMessage;
    case 'administrator':
    case 'auth_only':
      return adminInviteExistingAccountMessage;
    case 'invitation_pending':
      return adminInvitePendingMessage;
    case 'invalid_email':
      return 'Enter a valid email address.';
    case 'invalid_name':
      return "Enter the administrator's full name.";
    case 'forbidden':
      return 'You cannot manage administrator accounts.';
    case 'last_super_admin':
      return 'The last active Super Admin cannot be deactivated.';
    case 'email_failed':
      return serverMessage ??
          'The invitation email could not be sent. Use Resend.';
    default:
      final message = serverMessage?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Could not complete that request. Try again.';
  }
}
