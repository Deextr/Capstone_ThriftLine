import '../../admin/domain/auction_bidding_violations.dart';
import '../domain/confirmed_violation.dart';
import 'report_reasons.dart';

enum ConfirmedViolationCategoryFilter {
  all,
  lookingFor,
  auctionBidding,
  communityReport,
}

enum ConfirmedViolationPenaltyFilter {
  all,
  activeRestriction,
  warningOnly,
  resolvedOnly,
}

String confirmedViolationCategoryLabel(String category) {
  return switch (category) {
    'looking_for' => 'Looking For',
    'auction_bidding' => 'Auction bidding',
    _ => reportReasonLabel(category),
  };
}

String lookingForReportReasonLabel(String reason) {
  return switch (reason) {
    'spam' => 'Spam',
    'unrelated_content' => 'Unrelated content',
    'inappropriate_content' => 'Inappropriate content',
    'scam_or_suspicious' => 'Scam or suspicious activity',
    'other' => 'Other',
    _ => reason,
  };
}

String confirmedViolationTypeHeading(ConfirmedViolationSummary summary) {
  return switch (summary.source) {
    'looking_for' => 'Looking For guideline violation',
    'auction_bidding' => kAuctionNonPaymentViolationType,
    'community_report' => confirmedViolationCategoryLabel(summary.category),
    _ => 'Confirmed violation',
  };
}

String penaltyStatusLabel(String status) {
  return switch (status) {
    'permanent_disable' => 'Account disabled',
    'restricted' => 'Restriction active',
    'warning' => 'Warning on record',
    'resolved' => 'Review completed',
    _ => 'On record',
  };
}

String confirmedViolationPenaltySummary(ConfirmedViolationSummary summary) {
  if (summary.source == 'looking_for' &&
      summary.strikeNumber != null &&
      summary.strikeNumber! > 0) {
    return 'Strike ${summary.strikeNumber} · '
        '${penaltyStatusLabel(summary.penaltyStatus)}';
  }
  if (summary.source == 'auction_bidding') {
    final countLabel = summary.violationNumber != null &&
            summary.violationNumber! > 0
        ? formatOrdinalViolationCount(summary.violationNumber!)
        : null;
    final consequenceLabel = summary.consequence != null &&
            summary.consequence!.isNotEmpty
        ? consequenceDisplayLabel(summary.consequence!)
        : null;
    if (countLabel != null && consequenceLabel != null) {
      return '$countLabel · $consequenceLabel';
    }
    return countLabel ??
        consequenceLabel ??
        penaltyStatusLabel(summary.penaltyStatus);
  }
  return penaltyStatusLabel(summary.penaltyStatus);
}

String confirmedViolationCategoryFilterLabel(
  ConfirmedViolationCategoryFilter filter,
) {
  return switch (filter) {
    ConfirmedViolationCategoryFilter.all => 'All categories',
    ConfirmedViolationCategoryFilter.lookingFor => 'Looking For',
    ConfirmedViolationCategoryFilter.auctionBidding => 'Auction bidding',
    ConfirmedViolationCategoryFilter.communityReport => 'Community & orders',
  };
}

String confirmedViolationPenaltyFilterLabel(
  ConfirmedViolationPenaltyFilter filter,
) {
  return switch (filter) {
    ConfirmedViolationPenaltyFilter.all => 'All statuses',
    ConfirmedViolationPenaltyFilter.activeRestriction => 'Active restrictions',
    ConfirmedViolationPenaltyFilter.warningOnly => 'Warnings',
    ConfirmedViolationPenaltyFilter.resolvedOnly => 'Review completed',
  };
}

bool matchesCategoryFilter(
  ConfirmedViolationSummary item,
  ConfirmedViolationCategoryFilter filter,
) {
  return switch (filter) {
    ConfirmedViolationCategoryFilter.all => true,
    ConfirmedViolationCategoryFilter.lookingFor => item.source == 'looking_for',
    ConfirmedViolationCategoryFilter.auctionBidding =>
      item.source == 'auction_bidding',
    ConfirmedViolationCategoryFilter.communityReport =>
      item.source == 'community_report',
  };
}

bool matchesPenaltyFilter(
  String penaltyStatus,
  ConfirmedViolationPenaltyFilter filter,
) {
  return switch (filter) {
    ConfirmedViolationPenaltyFilter.all => true,
    ConfirmedViolationPenaltyFilter.activeRestriction =>
      penaltyStatus == 'restricted' || penaltyStatus == 'permanent_disable',
    ConfirmedViolationPenaltyFilter.warningOnly => penaltyStatus == 'warning',
    ConfirmedViolationPenaltyFilter.resolvedOnly =>
      penaltyStatus == 'resolved' || penaltyStatus == 'recorded',
  };
}

bool matchesConfirmedDateRange(
  DateTime confirmedAt,
  DateTime? from,
  DateTime? to,
) {
  final day = DateTime.utc(
    confirmedAt.year,
    confirmedAt.month,
    confirmedAt.day,
  );
  if (from != null) {
    final start = DateTime.utc(from.year, from.month, from.day);
    if (day.isBefore(start)) return false;
  }
  if (to != null) {
    final end = DateTime.utc(to.year, to.month, to.day);
    if (day.isAfter(end)) return false;
  }
  return true;
}

String resolutionFinancialLabel(String? value) {
  return switch (value) {
    'refund_buyer' => 'Refund issued to buyer',
    'release_seller' => 'Payment released to seller',
    _ => '',
  };
}

String enforcementReasonLabel(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  return switch (value) {
    'fulfillment_sla_72h' => 'Order not processed within the required time',
    _ => value.replaceAll('_', ' '),
  };
}
