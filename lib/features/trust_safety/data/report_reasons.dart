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

const List<ReportReason> kReportReasons = [
  ReportReason(
    slug: 'scam_or_fraud',
    label: 'Scam or Fraud',
    description: 'Suspected scam, payment fraud, or dishonest dealing',
    icon: Icons.warning_amber_rounded,
  ),
  ReportReason(
    slug: 'fake_product',
    label: 'Fake or Misrepresented Item',
    description: 'The item is fake or not what was listed',
    icon: Icons.cancel_outlined,
  ),
  ReportReason(
    slug: 'counterfeit_item',
    label: 'Counterfeit Item',
    description: 'A counterfeit of a known brand',
    icon: Icons.content_copy_outlined,
  ),
  ReportReason(
    slug: 'harassment',
    label: 'Harassment',
    description: 'Threatening, hostile, or harassing behavior',
    icon: Icons.mood_bad_outlined,
  ),
  ReportReason(
    slug: 'inappropriate_messages',
    label: 'Abusive Behavior',
    description: 'Offensive, abusive, or inappropriate messages',
    icon: Icons.chat_bubble_outline,
  ),
  ReportReason(
    slug: 'failure_to_ship',
    label: 'Suspicious Activity',
    description: 'Avoiding fulfillment or other suspicious conduct',
    icon: Icons.visibility_outlined,
  ),
  ReportReason(
    slug: 'item_not_as_described',
    label: 'Item Not as Described',
    description: 'The item does not match the listing',
    icon: Icons.difference_outlined,
  ),
  ReportReason(
    slug: 'fake_identity',
    label: 'Fake Identity',
    description: 'Using a fake identity or stolen photos',
    icon: Icons.person_off_outlined,
  ),
  ReportReason(
    slug: 'other',
    label: 'Other',
    description: 'Another community guideline concern',
    icon: Icons.more_horiz_outlined,
  ),
];

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
  for (final reason in kReportReasons) {
    if (reason.slug == slug) return reason;
  }
  return null;
}

String reportReasonLabel(String slug) {
  return reportReasonBySlug(slug)?.label ?? slug;
}

String reportStatusLabel(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' => 'Under Review',
    'action_taken' => 'Action Taken',
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
    'action_taken' => const Color(0xFF10B981),
    'resolved' => const Color(0xFF10B981),
    'dismissed' => const Color(0xFF64748B),
    _ => const Color(0xFF64748B),
  };
}

String reportStatusDescription(String status) {
  final normalized = reportStatusFromDb(status);
  return switch (normalized) {
    'under_review' => 'Your report is currently being reviewed.',
    'action_taken' => 'The review is complete and action was taken.',
    'resolved' => 'The review has been completed.',
    'dismissed' => 'The report was reviewed and dismissed.',
    _ => 'Open report details for the latest update.',
  };
}

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
