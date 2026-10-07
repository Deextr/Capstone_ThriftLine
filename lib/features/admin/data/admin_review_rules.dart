import '../../trust_safety/data/report_reasons.dart';
import '../../../widgets/thrift_widgets.dart';

const String kAdminReportOpenStatus = 'under_review';
const String kAdminReportNeedsEvidenceStatus = 'needs_more_evidence';
const List<String> kAdminReportClosedStatuses = ['resolved', 'dismissed'];
const List<String> kAdminReportDecisions = [
  'needs_more_evidence',
  'resolved',
  'dismissed',
];

const String kAdminDisputeOpenStatus = 'open';
const String kAdminDisputeClosedStatus = 'resolved';

const int kAdminResponseMinLength = 8;
const int kAdminNeedsMoreEvidenceMinLength = 20;
const int kAdminResponseMaxLength = 2000;
const int kAdminDisputeNoteMaxLength = 2000;
const String kAdminEvidenceBucket = 'report-evidence';
const int kAdminSignedUrlSeconds = 3600;

enum AdminQueueFilter { open, closed }

enum AdminReportListFilter {
  all,
  underReview,
  needsMoreEvidence,
  resolved,
  dismissed,
}

enum AdminReportKind { all, community, order, lookingFor }

enum AdminModerationCategory { community, order, lookingFor }

String adminModerationCategoryLabel(AdminModerationCategory category) =>
    switch (category) {
      AdminModerationCategory.community => 'Community Reports',
      AdminModerationCategory.order => 'Order Reports',
      AdminModerationCategory.lookingFor => 'Looking For Reports',
    };

String adminModerationCategoryParam(AdminModerationCategory category) =>
    switch (category) {
      AdminModerationCategory.community => 'community',
      AdminModerationCategory.order => 'order',
      AdminModerationCategory.lookingFor => 'looking_for',
    };

AdminModerationCategory? adminModerationCategoryFromParam(String? raw) =>
    switch (raw?.trim().toLowerCase()) {
      'community' => AdminModerationCategory.community,
      'order' || 'orders' => AdminModerationCategory.order,
      'looking_for' || 'looking-for' => AdminModerationCategory.lookingFor,
      _ => null,
    };

AdminModerationCategory adminModerationCategoryFromReportKind(
  AdminReportKind kind,
) => switch (kind) {
  AdminReportKind.community => AdminModerationCategory.community,
  AdminReportKind.order => AdminModerationCategory.order,
  AdminReportKind.lookingFor => AdminModerationCategory.lookingFor,
  AdminReportKind.all => AdminModerationCategory.community,
};

String adminModerationCaseKindLabel(String caseKind) => switch (caseKind) {
  'community_report' => 'Community Report',
  'order_report' => 'Order Report',
  'looking_for_report' => 'Looking For Report',
  _ => 'Case',
};

String adminModerationCaseKindShortLabel(String caseKind) => switch (caseKind) {
  'community_report' => 'Community',
  'order_report' => 'Order',
  'looking_for_report' => 'Looking For',
  _ => 'Case',
};

String adminModerationCaseRef(String caseId) =>
    '#${adminReportShortId(caseId)}';

String adminModerationStatusLabel({
  required String source,
  required String statusRaw,
}) => reportStatusLabel(statusRaw);

String adminModerationStatusFilterParam(AdminReportListFilter filter) =>
    switch (filter) {
      AdminReportListFilter.all => 'all',
      AdminReportListFilter.underReview => 'under_review',
      AdminReportListFilter.needsMoreEvidence => 'needs_more_evidence',
      AdminReportListFilter.resolved => 'resolved',
      AdminReportListFilter.dismissed => 'dismissed',
    };

enum AdminReportSort { newest, oldest }

const Set<String> kAdminOrderLinkedReasons = {
  'seller_not_processing_order',
  'counterfeit_received',
  'item_not_as_described',
  'undisclosed_damage',
  'buyer_delivery_pin_issue',
  'fake_product',
  'counterfeit_item',
  'failure_to_ship',
};

bool isAdminOrderReport({required String category, String? orderId}) {
  if (orderId != null && orderId.trim().isNotEmpty) return true;
  return kAdminOrderLinkedReasons.contains(category);
}

String adminReportKindLabel(AdminReportKind kind) => switch (kind) {
  AdminReportKind.all => 'All Reports',
  AdminReportKind.community => 'Community Reports',
  AdminReportKind.order => 'Order Reports',
  AdminReportKind.lookingFor => 'Looking For Reports',
};

String adminReportKindHubSubtitle(AdminReportKind kind) => switch (kind) {
  AdminReportKind.community =>
    'Seller listings and account behavior outside a specific order.',
  AdminReportKind.order =>
    'Problems tied to a purchase between a buyer and seller.',
  AdminReportKind.lookingFor => 'Inappropriate or abusive Looking For posts.',
  AdminReportKind.all => 'All report categories.',
};

AdminReportKind? adminReportKindFromQueuePath(String segment) =>
    switch (segment) {
      'community' => AdminReportKind.community,
      'orders' => AdminReportKind.order,
      'looking-for' => AdminReportKind.lookingFor,
      _ => null,
    };

String adminReportQueuePathSegment(AdminReportKind kind) => switch (kind) {
  AdminReportKind.community => 'community',
  AdminReportKind.order => 'orders',
  AdminReportKind.lookingFor => 'looking-for',
  AdminReportKind.all => '',
};

String adminReportKindOf({required String category, String? orderId}) =>
    isAdminOrderReport(category: category, orderId: orderId)
    ? 'Order'
    : 'Community';

String adminReportSortLabel(AdminReportSort sort) => switch (sort) {
  AdminReportSort.newest => 'Newest',
  AdminReportSort.oldest => 'Oldest',
};

String adminReportShortId(String id) {
  final compact = id.replaceAll('-', '');
  if (compact.length < 8) return compact.toUpperCase();
  return compact.substring(0, 8).toUpperCase();
}

String adminReportPreview(String details, {int maxLength = 90}) {
  final trimmed = details.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= maxLength) return trimmed;
  return '${trimmed.substring(0, maxLength).trimRight()}…';
}

bool isOpenReportStatus(String status) =>
    status == kAdminReportOpenStatus ||
    status == kAdminReportNeedsEvidenceStatus;

bool canDecideReport(String status) =>
    status == kAdminReportOpenStatus ||
    status == kAdminReportNeedsEvidenceStatus;

bool canResubmitReportEvidence(String status) =>
    status == kAdminReportNeedsEvidenceStatus;

bool isAllowedReportDecision(String decision) =>
    kAdminReportDecisions.contains(decision);

bool isOpenDisputeStatus(String status) => status == kAdminDisputeOpenStatus;

bool canCloseDispute(String status) => status == kAdminDisputeOpenStatus;

String adminQueueFilterLabel(AdminQueueFilter filter) => switch (filter) {
  AdminQueueFilter.open => 'Needs review',
  AdminQueueFilter.closed => 'Reviewed',
};

String adminReportListFilterLabel(AdminReportListFilter filter) =>
    switch (filter) {
      AdminReportListFilter.all => 'All',
      AdminReportListFilter.underReview => 'Under Review',
      AdminReportListFilter.needsMoreEvidence => 'Needs More Evidence',
      AdminReportListFilter.resolved => 'Resolved',
      AdminReportListFilter.dismissed => 'Dismissed',
    };

List<String>? adminReportListFilterStatuses(AdminReportListFilter filter) =>
    switch (filter) {
      AdminReportListFilter.all => null,
      AdminReportListFilter.underReview => [kAdminReportOpenStatus],
      AdminReportListFilter.needsMoreEvidence => [
        kAdminReportNeedsEvidenceStatus,
      ],
      AdminReportListFilter.resolved => ['resolved'],
      AdminReportListFilter.dismissed => ['dismissed'],
    };

String adminQueueStatusLine(int count, String state) {
  if (count <= 0) return 'None waiting';
  return '$count $state';
}

String orderReportFinancialLabel(String financial) => switch (financial) {
  'refund_buyer' => 'Refund buyer',
  'release_seller' => 'Release payment to seller',
  _ => financial,
};

String reportDecisionCta(String decision) => switch (decision) {
  'needs_more_evidence' => 'Request more evidence',
  'resolved' => 'Resolve report',
  'dismissed' => 'Dismiss report',
  _ => 'Save decision',
};

String adminReportActivityTitle(String status) => switch (status) {
  'needs_more_evidence' => 'More evidence requested',
  'resolved' => 'Report resolved',
  'dismissed' => 'Report dismissed',
  'action_taken' => 'Report resolved',
  _ => 'Report reviewed',
};

String adminApplicationActivityTitle(String status) => switch (status) {
  'approved' => 'Seller application approved',
  'rejected' => 'Seller application rejected',
  _ => 'Seller application reviewed',
};

String reportDecisionLabel(String decision) => switch (decision) {
  'needs_more_evidence' => 'Request More Evidence',
  'resolved' => 'Resolved',
  'dismissed' => 'Dismissed',
  _ => decision,
};

String reportDecisionHint(String decision) => switch (decision) {
  'needs_more_evidence' =>
    'Tell the reporter exactly what photos or details to add.',
  'resolved' => 'The case was reviewed and closed.',
  'dismissed' => 'No actionable violation was confirmed.',
  _ => '',
};

String adminReportDecisionConfirmBody({
  required String decision,
  String? orderId,
}) {
  final linkedOrder = orderId != null && orderId.trim().isNotEmpty;
  if (decision == 'dismissed' && linkedOrder) {
    return 'The reporter will see this decision and your response. '
        'The delivery payment hold for this order is removed and the order '
        'lifecycle resumes when eligible. The buyer is not refunded.';
  }
  if (decision == 'needs_more_evidence') {
    return 'The reporter will see your instructions and can submit '
        'additional evidence if attempts remain.';
  }
  return 'The reporter will see this decision and your response. '
      'This does not ban the reported user or change payments.';
}

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

String? adminResponseError(String value, {String? decision}) {
  final trimmed = value.trim();
  final minLen = decision == 'needs_more_evidence'
      ? kAdminNeedsMoreEvidenceMinLength
      : kAdminResponseMinLength;
  if (trimmed.length < minLen) {
    return decision == 'needs_more_evidence'
        ? 'Explain what evidence is missing (at least $minLen characters).'
        : 'Write a short response for the reporter.';
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
  'needs_more_evidence' => BadgeVariant.warning,
  'resolved' ||
  'approved' ||
  'paid' ||
  'shipped' ||
  'delivered' ||
  'completed' => BadgeVariant.success,
  'dismissed' || 'cancelled' => BadgeVariant.neutral,
  'rejected' || 'disputed' => BadgeVariant.error,
  'action_taken' => BadgeVariant.success,
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
