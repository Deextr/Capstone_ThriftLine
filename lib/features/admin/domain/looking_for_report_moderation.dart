import '../../buyer/domain/looking_for_lifecycle.dart';

/// Admin review target from report submission (not an auto-close deadline).
const Duration lookingForReportReviewTarget = Duration(hours: 24);

const Duration lookingForExpiryUrgentThreshold = Duration(hours: 4);
const Duration lookingForExpiryReviewSoonThreshold = Duration(hours: 18);
const Duration lookingForExpiringSoonWindow = Duration(hours: 24);

enum LookingForReportReviewTargetBand { withinTarget, reviewSoon, overdue }

enum LookingForPostExpiryUrgencyBand {
  active,
  reviewSoon,
  urgent,
  expiredReviewRequired,
}

enum LookingForReportSeverityBand { low, elevated, high }

int lookingForReportReasonSeverityScore(String reason) {
  switch (reason.trim().toLowerCase()) {
    case 'explicit_content':
      return 1000;
    case 'scam_or_suspicious':
      return 900;
    case 'inappropriate_content':
      return 800;
    case 'spam':
      return 250;
    case 'unrelated_content':
      return 200;
    default:
      return 150;
  }
}

LookingForReportSeverityBand lookingForReportSeverityBand(String reason) {
  final score = lookingForReportReasonSeverityScore(reason);
  if (score >= 800) return LookingForReportSeverityBand.high;
  if (score >= 250) return LookingForReportSeverityBand.elevated;
  return LookingForReportSeverityBand.low;
}

LookingForReportReviewTargetBand lookingForReportReviewTargetBand({
  required DateTime reportCreatedAt,
  required DateTime serverNow,
}) {
  final elapsed = serverNow.toUtc().difference(reportCreatedAt.toUtc());
  if (elapsed >= lookingForReportReviewTarget) {
    return LookingForReportReviewTargetBand.overdue;
  }
  if (elapsed >= const Duration(hours: 21)) {
    return LookingForReportReviewTargetBand.reviewSoon;
  }
  return LookingForReportReviewTargetBand.withinTarget;
}

String lookingForReportReviewTargetLabel(
  LookingForReportReviewTargetBand band,
) => switch (band) {
  LookingForReportReviewTargetBand.withinTarget => 'Within target',
  LookingForReportReviewTargetBand.reviewSoon => 'Review soon',
  LookingForReportReviewTargetBand.overdue => 'Overdue',
};

bool lookingForReportIsOpen(String status) =>
    status == 'under_review' || status == 'needs_more_evidence';

bool lookingForReportExpiredReviewRequired({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
}) {
  if (!lookingForReportIsOpen(status)) return false;
  final expiry = expiresAt?.toUtc();
  if (expiry == null) return false;
  return !expiry.isAfter(serverNow.toUtc());
}

LookingForPostExpiryUrgencyBand lookingForPostExpiryUrgencyBand({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
}) {
  if (lookingForReportExpiredReviewRequired(
    status: status,
    expiresAt: expiresAt,
    serverNow: serverNow,
  )) {
    return LookingForPostExpiryUrgencyBand.expiredReviewRequired;
  }
  if (!lookingForReportIsOpen(status) || expiresAt == null) {
    return LookingForPostExpiryUrgencyBand.active;
  }
  final remaining = expiresAt.toUtc().difference(serverNow.toUtc());
  if (remaining <= Duration.zero) {
    return LookingForPostExpiryUrgencyBand.expiredReviewRequired;
  }
  if (remaining <= lookingForExpiryUrgentThreshold) {
    return LookingForPostExpiryUrgencyBand.urgent;
  }
  if (remaining <= lookingForExpiryReviewSoonThreshold) {
    return LookingForPostExpiryUrgencyBand.reviewSoon;
  }
  return LookingForPostExpiryUrgencyBand.active;
}

String lookingForPostExpiryUrgencyHeadline({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
}) {
  final band = lookingForPostExpiryUrgencyBand(
    status: status,
    expiresAt: expiresAt,
    serverNow: serverNow,
  );
  return switch (band) {
    LookingForPostExpiryUrgencyBand.expiredReviewRequired => _expiredAgoLabel(
      expiresAt,
      serverNow,
    ),
    LookingForPostExpiryUrgencyBand.urgent => _expiresInShort(
      expiresAt,
      serverNow,
    ),
    LookingForPostExpiryUrgencyBand.reviewSoon => _expiresInShort(
      expiresAt,
      serverNow,
    ),
    LookingForPostExpiryUrgencyBand.active =>
      expiresAt != null
          ? lookingForExpirationLabel(
              expiresAt: expiresAt,
              serverNow: serverNow,
            )
          : 'Active post',
  };
}

String lookingForModerationStatusDisplayLabel({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
}) {
  if (lookingForReportExpiredReviewRequired(
    status: status,
    expiresAt: expiresAt,
    serverNow: serverNow,
  )) {
    return 'Expired — Review Required';
  }
  return switch (status) {
    'under_review' => 'Under review',
    'needs_more_evidence' => 'Needs more evidence',
    'resolved' => 'Resolved',
    'dismissed' => 'Dismissed',
    _ => 'Under review',
  };
}

/// Human-readable elapsed time (full days once ≥ 24 hours).
String formatLookingForElapsedAgoLabel(Duration elapsed) {
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return 'Just expired';
  }
  if (elapsed.inMinutes < 60) {
    final m = elapsed.inMinutes;
    return m == 1 ? 'Expired 1 minute ago' : 'Expired $m minutes ago';
  }
  if (elapsed.inHours < 24) {
    final h = elapsed.inHours;
    return h == 1 ? 'Expired 1 hour ago' : 'Expired $h hours ago';
  }
  final days = elapsed.inHours ~/ 24;
  return days == 1 ? 'Expired 1 day ago' : 'Expired $days days ago';
}

/// Human-readable time until expiry (full days once ≥ 24 hours).
String formatLookingForRemainingLabel(Duration remaining) {
  if (remaining.isNegative || remaining.inMinutes < 1) {
    return 'Just expired';
  }
  if (remaining.inMinutes < 60) {
    final m = remaining.inMinutes;
    return m == 1 ? 'Expires in 1 minute' : 'Expires in $m minutes';
  }
  if (remaining.inHours < 24) {
    final h = remaining.inHours;
    return h == 1 ? 'Expires in 1 hour' : 'Expires in $h hours';
  }
  final days = remaining.inHours ~/ 24;
  return days == 1 ? 'Expires in 1 day' : 'Expires in $days days';
}

String _expiresInShort(DateTime? expiresAt, DateTime serverNow) {
  if (expiresAt == null) return 'Expiring soon';
  return formatLookingForRemainingLabel(
    expiresAt.toUtc().difference(serverNow.toUtc()),
  );
}

String _expiredAgoLabel(DateTime? expiresAt, DateTime serverNow) {
  if (expiresAt == null) return 'Expired';
  return formatLookingForElapsedAgoLabel(
    serverNow.toUtc().difference(expiresAt.toUtc()),
  );
}

/// Dispute workflow status only (not post expiration).
String lookingForDisputeStatusTableLabel(String status) => switch (status) {
  'under_review' => 'Under review',
  'needs_more_evidence' => 'Needs more evidence',
  'resolved' => 'Resolved',
  'dismissed' => 'Dismissed',
  'action_taken' => 'Resolved',
  _ => 'Under review',
};

/// Optional one-line hint when post expired but dispute is still open.
String? lookingForDisputeStatusTableHint({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
}) {
  if (!lookingForReportExpiredReviewRequired(
    status: status,
    expiresAt: expiresAt,
    serverNow: serverNow,
  )) {
    return null;
  }
  return 'Post expired — decision still required';
}

/// Post lifecycle line for the disputes table (separate from dispute status).
String lookingForPostStatusTableLabel({
  required String disputeStatus,
  required DateTime? expiresAt,
  required DateTime serverNow,
  String? decisionOutcome,
}) {
  if (decisionOutcome == 'violation_confirmed') {
    return 'Removed by moderation';
  }
  final expiry = expiresAt?.toUtc();
  if (expiry == null) {
    return lookingForReportIsOpen(disputeStatus) ? 'Active' : '—';
  }
  final now = serverNow.toUtc();
  if (expiry.isAfter(now)) {
    return formatLookingForRemainingLabel(expiry.difference(now));
  }
  return formatLookingForElapsedAgoLabel(now.difference(expiry));
}

int lookingForReportPriorityScore({
  required String reason,
  required String status,
  required DateTime? expiresAt,
  required DateTime reportCreatedAt,
  required int openReportsOnPost,
  required int confirmedViolations,
  required DateTime serverNow,
}) {
  if (!lookingForReportIsOpen(status)) return 0;
  var score = lookingForReportReasonSeverityScore(reason);
  if (expiresAt != null) {
    final hoursToExpiry =
        expiresAt.toUtc().difference(serverNow.toUtc()).inMinutes / 60.0;
    if (hoursToExpiry <= 0) {
      score += 350;
    } else if (hoursToExpiry <= 4) {
      score += 500;
    } else if (hoursToExpiry <= 18) {
      score += 300;
    } else if (hoursToExpiry <= 24) {
      score += 200;
    }
  }
  final hoursSince =
      serverNow.toUtc().difference(reportCreatedAt.toUtc()).inMinutes / 60.0;
  if (hoursSince >= 24) {
    score += 400;
  } else if (hoursSince >= 21) {
    score += 250;
  }
  score += (openReportsOnPost - 1).clamp(0, 20) * 15;
  score += confirmedViolations.clamp(0, 5) * 8;
  return score;
}

int compareLookingForReportPriority({
  required String reasonA,
  required String statusA,
  required DateTime? expiresA,
  required DateTime createdA,
  required int openA,
  required int violationsA,
  required String reasonB,
  required String statusB,
  required DateTime? expiresB,
  required DateTime createdB,
  required int openB,
  required int violationsB,
  required DateTime serverNow,
}) {
  final scoreA = lookingForReportPriorityScore(
    reason: reasonA,
    status: statusA,
    expiresAt: expiresA,
    reportCreatedAt: createdA,
    openReportsOnPost: openA,
    confirmedViolations: violationsA,
    serverNow: serverNow,
  );
  final scoreB = lookingForReportPriorityScore(
    reason: reasonB,
    status: statusB,
    expiresAt: expiresB,
    reportCreatedAt: createdB,
    openReportsOnPost: openB,
    confirmedViolations: violationsB,
    serverNow: serverNow,
  );
  if (scoreA != scoreB) return scoreB.compareTo(scoreA);
  if (lookingForReportIsOpen(statusA) && lookingForReportIsOpen(statusB)) {
    return createdA.compareTo(createdB);
  }
  return createdB.compareTo(createdA);
}

bool lookingForSnapshotDiffersFromLive({
  required String? snapshotTitle,
  required String? snapshotDescription,
  required String liveTitle,
  required String liveDescription,
}) {
  final a = normalizeLookingForText(snapshotTitle ?? '');
  final b = normalizeLookingForText(liveTitle);
  final c = normalizeLookingForText(snapshotDescription ?? '');
  final d = normalizeLookingForText(liveDescription);
  return a != b || c != d;
}
