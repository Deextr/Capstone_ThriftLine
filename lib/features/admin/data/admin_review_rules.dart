import '../../../widgets/thrift_widgets.dart';

const String kAdminReportOpenStatus = 'under_review';
const List<String> kAdminReportClosedStatuses = [
  'action_taken',
  'resolved',
  'dismissed',
];
const List<String> kAdminReportDecisions = [
  'action_taken',
  'resolved',
  'dismissed',
];

const String kAdminDisputeOpenStatus = 'open';
const String kAdminDisputeClosedStatus = 'resolved';

const int kAdminResponseMinLength = 8;
const int kAdminResponseMaxLength = 2000;
const int kAdminDisputeNoteMaxLength = 2000;

const String kAdminEvidenceBucket = 'report-evidence';
const int kAdminSignedUrlSeconds = 3600;

enum AdminQueueFilter { open, closed }

bool isOpenReportStatus(String status) => status == kAdminReportOpenStatus;

bool canDecideReport(String status) => status == kAdminReportOpenStatus;

bool isAllowedReportDecision(String decision) =>
    kAdminReportDecisions.contains(decision);

bool isOpenDisputeStatus(String status) => status == kAdminDisputeOpenStatus;

bool canCloseDispute(String status) => status == kAdminDisputeOpenStatus;

String adminQueueFilterLabel(AdminQueueFilter filter) => switch (filter) {
  AdminQueueFilter.open => 'Needs review',
  AdminQueueFilter.closed => 'Reviewed',
};

/// Compact queue count. [state] is the human status, such as "under review".
String adminQueueStatusLine(int count, String state) {
  if (count <= 0) return 'None waiting';
  return '$count $state';
}

String reportDecisionCta(String decision) => switch (decision) {
  'action_taken' => 'Record action taken',
  'resolved' => 'Resolve report',
  'dismissed' => 'Dismiss report',
  _ => 'Save decision',
};

String adminReportActivityTitle(String status) => switch (status) {
  'action_taken' => 'Action taken on a report',
  'resolved' => 'Report resolved',
  'dismissed' => 'Report dismissed',
  _ => 'Report reviewed',
};

String adminApplicationActivityTitle(String status) => switch (status) {
  'approved' => 'Seller application approved',
  'rejected' => 'Seller application rejected',
  _ => 'Seller application reviewed',
};

String reportDecisionLabel(String decision) => switch (decision) {
  'action_taken' => 'Action Taken',
  'resolved' => 'Resolved',
  'dismissed' => 'Dismissed',
  _ => decision,
};

String reportDecisionHint(String decision) => switch (decision) {
  'action_taken' => 'The report was reviewed and action was warranted.',
  'resolved' => 'The case was reviewed and closed.',
  'dismissed' => 'No actionable violation was confirmed.',
  _ => '',
};

String disputeStatusLabel(String status) => switch (status) {
  'open' => 'Open',
  'resolved' => 'Resolved',
  _ => status,
};

String verificationStatusLabel(String status) => switch (status) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _ => status,
};

String accountRoleLabel(String? role) => switch (role) {
  'seller' => 'Seller',
  'admin' => 'Admin',
  'buyer' => 'Buyer',
  _ => 'Member',
};

String adminHandle(String username, String displayName) {
  if (username.trim().isNotEmpty) return '@${username.trim()}';
  if (displayName.trim().isNotEmpty) return displayName.trim();
  return 'Member';
}

String? adminResponseError(String value) {
  final trimmed = value.trim();
  if (trimmed.length < kAdminResponseMinLength) {
    return 'Write a short response for the reporter.';
  }
  if (trimmed.length > kAdminResponseMaxLength) {
    return 'Keep the response under 2,000 characters.';
  }
  return null;
}

String? adminDisputeNoteError(String value) {
  if (value.trim().length > kAdminDisputeNoteMaxLength) {
    return 'Keep the note under 2,000 characters.';
  }
  return null;
}

BadgeVariant adminStatusBadgeVariant(String status) => switch (status) {
  'under_review' || 'pending' || 'open' => BadgeVariant.warning,
  'action_taken' || 'resolved' || 'approved' => BadgeVariant.success,
  'dismissed' => BadgeVariant.neutral,
  'rejected' => BadgeVariant.error,
  _ => BadgeVariant.neutral,
};

String adminEvidenceCountLabel(int count) {
  if (count <= 0) return '';
  if (count == 1) return '1 photo';
  return '$count photos';
}

String adminFriendlyError(Object error, String fallback) {
  final text = error.toString();
  if (text.contains('Only an admin')) {
    return 'Only an admin can take this action.';
  }
  if (text.contains('already been reviewed')) {
    return 'This report has already been reviewed.';
  }
  return fallback;
}
