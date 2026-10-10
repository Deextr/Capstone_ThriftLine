import 'package:flutter/material.dart';

import '../../../core/utils/report_status.dart';

class ReportReason {
  const ReportReason({
    required this.slug,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String slug;
  final String label;
  final String description;
  final IconData icon;
}

/// Community reports — seller/listing conduct without a specific order issue.
const List<ReportReason> kCommunityReportReasons = [
  ReportReason(
    slug: 'scam_or_fraud',
    label: 'Scam or Fraud',
    description: 'Suspected scam, payment fraud, or dishonest dealing',
    icon: Icons.warning_amber_rounded,
  ),
  ReportReason(
    slug: 'counterfeit_item',
    label: 'Counterfeit or Fake Items',
    description: 'Listings appear counterfeit, fake, or not genuine',
    icon: Icons.content_copy_outlined,
  ),
  ReportReason(
    slug: 'harassment',
    label: 'Harassment or Abusive Behavior',
    description: 'Threatening, harassing, or abusive conduct',
    icon: Icons.mood_bad_outlined,
  ),
  ReportReason(
    slug: 'suspicious_activity',
    label: 'Suspicious Activity',
    description: 'Suspicious marketplace or account behavior',
    icon: Icons.visibility_outlined,
  ),
  ReportReason(
    slug: 'misleading_listing',
    label: 'Misleading Listing or Information',
    description: 'Listing or profile information appears misleading',
    icon: Icons.info_outline,
  ),
  ReportReason(
    slug: 'fake_identity',
    label: 'Fake Identity or Impersonation',
    description: 'Fake identity, stolen photos, or impersonation',
    icon: Icons.person_off_outlined,
  ),
  ReportReason(
    slug: 'other',
    label: 'Other',
    description: 'Another community guideline concern',
    icon: Icons.more_horiz_outlined,
  ),
];

/// Order reports — buyer or seller issues tied to a purchase.
const List<ReportReason> kOrderBuyerReportReasons = [
  ReportReason(
    slug: 'seller_not_processing_order',
    label: 'Seller Did Not Process Order',
    description: 'Order stuck preparing or not shipped for too long',
    icon: Icons.hourglass_empty_outlined,
  ),
  ReportReason(
    slug: 'counterfeit_received',
    label: 'Fake / Counterfeit Item Received',
    description: 'Item received appears fake or counterfeit',
    icon: Icons.content_copy_outlined,
  ),
  ReportReason(
    slug: 'item_not_as_described',
    label: 'Item Not as Described',
    description: 'Item differs materially from the listing',
    icon: Icons.difference_outlined,
  ),
  ReportReason(
    slug: 'undisclosed_damage',
    label: 'Undisclosed Damage',
    description: 'Damage was not disclosed before purchase',
    icon: Icons.broken_image_outlined,
  ),
  ReportReason(
    slug: 'other',
    label: 'Other',
    description: 'Another order-related problem',
    icon: Icons.more_horiz_outlined,
  ),
];

const List<ReportReason> kOrderSellerReportReasons = [
  ReportReason(
    slug: 'buyer_delivery_pin_issue',
    label: 'Buyer Did Not Provide Delivery PIN',
    description: 'Buyer refused or failed to provide the delivery PIN',
    icon: Icons.pin_outlined,
  ),
  ReportReason(
    slug: 'other',
    label: 'Other',
    description: 'Another order-related problem',
    icon: Icons.more_horiz_outlined,
  ),
];

/// Legacy alias for screens still importing [kReportReasons].
const List<ReportReason> kReportReasons = kCommunityReportReasons;

const int kReportMaxEvidenceAttempts = 3;

const int kReportDetailsMinLength = 10;
const int kReportDetailsMaxLength = 1000;

/// Returned by [submit_report] for cooldown / duplicate / burst limits.
const String kReportSubmitTooFastMessage =
    "You're submitting reports too quickly. Please wait a moment and try again.";
const int kReportEvidenceMinCount = 1;
const int kReportEvidenceMaxCount = 3;
const int kReportEvidenceMaxBytes = 5 * 1024 * 1024;

const Set<String> kReportImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
const Set<String> kReportImageMimeTypes = {
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
};

ReportReason? reportReasonBySlug(String slug) {
  for (final reason in [
    ...kCommunityReportReasons,
    ...kOrderBuyerReportReasons,
    ...kOrderSellerReportReasons,
  ]) {
    if (reason.slug == slug) return reason;
  }
  return switch (slug) {
    'fake_item' || 'fake_product' => kCommunityReportReasons.firstWhere(
      (r) => r.slug == 'counterfeit_item',
    ),
    'abusive_behavior' || 'inappropriate_messages' =>
      kCommunityReportReasons.firstWhere((r) => r.slug == 'harassment'),
    'failure_to_ship' => kCommunityReportReasons.firstWhere(
      (r) => r.slug == 'suspicious_activity',
    ),
    _ => null,
  };
}

String reportReasonLabel(String slug) {
  return reportReasonBySlug(slug)?.label ?? slug;
}

String reportStatusLabel(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' => 'Under Review',
    'needs_more_evidence' => 'Needs More Evidence',
    'action_taken' => 'Resolved',
    'resolved' => 'Resolved',
    'dismissed' => 'Dismissed',
    _ =>
      normalized
          .split('_')
          .map(
            (part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}',
          )
          .join(' '),
  };
}

Color reportStatusColor(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' => const Color(0xFFF59E0B),
    'needs_more_evidence' => const Color(0xFFF59E0B),
    'action_taken' => const Color(0xFF10B981),
    'resolved' => const Color(0xFF10B981),
    'dismissed' => const Color(0xFF64748B),
    _ => const Color(0xFF64748B),
  };
}

String reportStatusDescription(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' =>
      "We're reviewing your report and the evidence you submitted. "
          "You'll be notified when there is an update.",
    'needs_more_evidence' =>
      'More evidence is required. Read the admin message below and '
          'submit additional evidence if you still have attempts left.',
    'action_taken' =>
      "We've completed our review and taken the appropriate action.",
    'resolved' => "We've completed our review and closed your report.",
    'dismissed' =>
      "We reviewed your report, but there wasn't enough evidence to "
          'support the claim.',
    _ => 'Open this page anytime for the latest update on your report.',
  };
}

IconData reportStatusIcon(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' => Icons.schedule_rounded,
    'needs_more_evidence' => Icons.add_photo_alternate_outlined,
    'action_taken' => Icons.gavel_rounded,
    'resolved' => Icons.check_circle_outline_rounded,
    'dismissed' => Icons.info_outline_rounded,
    _ => Icons.flag_outlined,
  };
}

/// Short, buyer-facing reference derived from the report UUID (not a DB column).
String reportReferenceLabel(String reportId) {
  final compact = reportId.replaceAll('-', '').trim();
  if (compact.length < 6) return 'Report';
  return '#${compact.substring(0, 6).toUpperCase()}';
}

bool reportStatusIsClosed(String status) {
  final normalized = reportStatusFromDb(status);
  return normalized == 'resolved' ||
      normalized == 'dismissed' ||
      normalized == 'action_taken';
}

bool reportStatusAllowsResubmit(String status) =>
    reportStatusFromDb(status) == 'needs_more_evidence';

String? reportDetailsError(String details) {
  final trimmed = details.trim();
  if (trimmed.length < kReportDetailsMinLength) {
    return 'Please add a bit more detail.';
  }
  if (trimmed.length > kReportDetailsMaxLength) {
    return 'Keep your report under 1,000 characters.';
  }
  return null;
}

/// Community seller reports: details optional unless reason is [other].
String? communityReportDetailsError(String details, String? categorySlug) {
  final trimmed = details.trim();
  if (trimmed.length > kReportDetailsMaxLength) {
    return 'Keep your report under 1,000 characters.';
  }
  if (categorySlug == 'other' && trimmed.length < kReportDetailsMinLength) {
    return 'Please describe the issue.';
  }
  return null;
}

String? deliveryFailureOtherDetailsError(String details) {
  final trimmed = details.trim();
  if (trimmed.isEmpty) {
    return 'Please describe the delivery problem.';
  }
  if (trimmed.length < kReportDetailsMinLength) {
    return 'Please add a bit more detail.';
  }
  if (trimmed.length > kReportDetailsMaxLength) {
    return 'Keep your description under 1,000 characters.';
  }
  return null;
}

bool isAllowedReportImageName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  return kReportImageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

String reportImageExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return 'jpg';
  final ext = name.substring(dot + 1).toLowerCase();
  return kReportImageExtensions.contains(ext) ? ext : 'jpg';
}

String reportImageContentType(String name) {
  return switch (reportImageExtension(name)) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
