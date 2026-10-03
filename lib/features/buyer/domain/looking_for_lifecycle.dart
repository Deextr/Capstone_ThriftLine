import 'package:intl/intl.dart';

import '../../../models/enums.dart';
import '../../../models/looking_for_model.dart';

/// How long a new or reposted Looking For request stays public.
const Duration lookingForActiveLifetime = Duration(days: 3);

/// Posts counted toward the rolling window, including reposts.
const int lookingForDailyPostLimit = 5;

const Duration lookingForPostWindow = Duration(hours: 24);

/// Minimum gap between create and repost submissions.
const Duration lookingForPostCooldown = Duration(seconds: 45);

const int lookingForReportDailyLimit = 10;

const Duration lookingForReportCooldown = Duration(seconds: 20);

const int lookingForReportDetailsMax = 400;

/// Shared with `looking_for_is_near_duplicate` in the lifecycle migration.
const double lookingForNearDuplicateJaccard = 0.74;

const int lookingForNearDuplicateSharedTokens = 3;

const double lookingForShortJaccard = 0.85;

const int lookingForShortSharedTokens = 2;

const double lookingForTrigramThreshold = 0.9;

const Set<String> lookingForStopwords = {
  'looking',
  'for',
  'a',
  'an',
  'the',
  'need',
  'needed',
  'want',
  'wanted',
  'i',
  'im',
  'my',
  'please',
  'find',
  'searching',
  'search',
  'iso',
  'anyone',
  'have',
  'has',
  'with',
  'and',
  'or',
  'of',
  'to',
  'me',
  'some',
  'buy',
  'buying',
};

enum LookingForLifecycle {
  active,
  expired,
  removed,
  closed,
  fulfilled,
  deleted,
}

enum LookingForStrikeConsequence { warning, restriction, permanentDisable }

/// Server clock plus three days. [createdAt] is not trusted from the device
/// when the database assigns it; this mirrors that rule for tests.
DateTime lookingForExpiresAt(DateTime createdAt) =>
    createdAt.toUtc().add(lookingForActiveLifetime);

LookingForLifecycle classifyLookingFor({
  required String status,
  required DateTime? expiresAt,
  required DateTime serverNow,
  DateTime? moderationRemovedAt,
  DateTime? ownerDeletedAt,
}) {
  if (ownerDeletedAt != null) return LookingForLifecycle.deleted;
  if (moderationRemovedAt != null) return LookingForLifecycle.removed;
  switch (status) {
    case 'closed':
      return LookingForLifecycle.closed;
    case 'fulfilled':
      return LookingForLifecycle.fulfilled;
  }
  final expiry = expiresAt?.toUtc();
  final now = serverNow.toUtc();
  if (expiry != null && !expiry.isAfter(now)) {
    return LookingForLifecycle.expired;
  }
  return LookingForLifecycle.active;
}

bool lookingForVisibleInBrowse(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.active;

bool lookingForVisibleInMyActive(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.active;

bool lookingForVisibleInInactive(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.expired ||
    lifecycle == LookingForLifecycle.removed ||
    lifecycle == LookingForLifecycle.closed ||
    lifecycle == LookingForLifecycle.fulfilled;

bool lookingForCanRepost(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.expired;

bool lookingForCanDelete(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.active ||
    lifecycle == LookingForLifecycle.expired ||
    lifecycle == LookingForLifecycle.closed ||
    lifecycle == LookingForLifecycle.fulfilled;

bool lookingForCanEdit(LookingForLifecycle lifecycle) =>
    lifecycle == LookingForLifecycle.active;

/// Expiration is a normal lifecycle change. It never counts as a strike.
bool lookingForExpirationCountsAsStrike() => false;

LookingForStrikeConsequence lookingForStrikeConsequence(int confirmedOffenses) {
  if (confirmedOffenses <= 1) return LookingForStrikeConsequence.warning;
  if (confirmedOffenses == 2) return LookingForStrikeConsequence.restriction;
  return LookingForStrikeConsequence.permanentDisable;
}

String normalizeLookingForText(String input) {
  final lower = input.trim().toLowerCase();
  final stripped = lower.replaceAll(RegExp('[^a-z0-9\\s]'), '');
  return stripped.replaceAll(RegExp('\\s+'), ' ').trim();
}

Set<String> lookingForContentTokens(String input) {
  final normalized = normalizeLookingForText(input);
  if (normalized.isEmpty) return const {};
  return normalized
      .split(' ')
      .where(
        (token) => token.isNotEmpty && !lookingForStopwords.contains(token),
      )
      .toSet();
}

Set<String> lookingForTrigrams(String normalized) {
  final padded = '  $normalized ';
  final grams = <String>{};
  for (var i = 0; i <= padded.length - 3; i++) {
    grams.add(padded.substring(i, i + 3));
  }
  return grams;
}

double lookingForTrigramSimilarity(String a, String b) {
  final left = lookingForTrigrams(normalizeLookingForText(a));
  final right = lookingForTrigrams(normalizeLookingForText(b));
  if (left.isEmpty || right.isEmpty) return 0;
  final union = left.union(right).length;
  if (union == 0) return 0;
  return left.intersection(right).length / union;
}

/// True when two requests are the same or highly similar.
///
/// Compares the caller's active requests on the server. An explicit repost
/// excludes its own expired source before this check runs.
bool lookingForTextsMatch(String a, String b) {
  final left = normalizeLookingForText(a);
  final right = normalizeLookingForText(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  final leftTokens = lookingForContentTokens(left);
  final rightTokens = lookingForContentTokens(right);
  if (leftTokens.isEmpty || rightTokens.isEmpty) return false;
  final shared = leftTokens.intersection(rightTokens).length;
  final union = leftTokens.union(rightTokens).length;
  if (union == 0) return false;
  final jaccard = shared / union;
  if (jaccard >= lookingForNearDuplicateJaccard &&
      shared >= lookingForNearDuplicateSharedTokens) {
    return true;
  }
  if (jaccard >= lookingForShortJaccard &&
      shared >= lookingForShortSharedTokens) {
    return true;
  }
  if (shared >= lookingForShortSharedTokens &&
      lookingForTrigramSimilarity(left, right) >= lookingForTrigramThreshold) {
    return true;
  }
  return false;
}

int lookingForPostsInWindow(
  Iterable<DateTime> activityAt, {
  required DateTime serverNow,
}) {
  final cutoff = serverNow.toUtc().subtract(lookingForPostWindow);
  return activityAt.where((stamp) => !stamp.toUtc().isBefore(cutoff)).length;
}

bool lookingForRateLimitAllows(
  Iterable<DateTime> activityAt, {
  required DateTime serverNow,
}) =>
    lookingForPostsInWindow(activityAt, serverNow: serverNow) <
    lookingForDailyPostLimit;

bool lookingForCooldownClear({
  DateTime? lastActivityAt,
  required DateTime serverNow,
}) {
  if (lastActivityAt == null) return true;
  return !serverNow.toUtc().isBefore(
    lastActivityAt.toUtc().add(lookingForPostCooldown),
  );
}

String lookingForExpirationLabel({
  required DateTime expiresAt,
  required DateTime serverNow,
}) {
  final remaining = expiresAt.toUtc().difference(serverNow.toUtc());
  if (remaining.inSeconds <= 0) return 'Expired';
  if (remaining.inMinutes < 60) {
    final minutes = remaining.inMinutes.clamp(1, 59);
    return minutes == 1 ? 'Expires in 1 minute' : 'Expires in $minutes minutes';
  }
  if (remaining.inHours < 24) {
    final hours = remaining.inHours;
    return hours == 1 ? 'Expires in 1 hour' : 'Expires in $hours hours';
  }
  if (remaining.inHours < 48) return 'Expires tomorrow';
  final days = remaining.inDays;
  return days == 1 ? 'Expires tomorrow' : 'Expires in $days days';
}

String lookingForLifecycleLabel(
  LookingForLifecycle lifecycle, {
  DateTime? expiresAt,
  DateTime? serverNow,
}) {
  return switch (lifecycle) {
    LookingForLifecycle.active when expiresAt != null && serverNow != null =>
      lookingForExpirationLabel(expiresAt: expiresAt, serverNow: serverNow),
    LookingForLifecycle.active => 'Active',
    LookingForLifecycle.expired => 'Expired',
    LookingForLifecycle.removed => 'Removed',
    LookingForLifecycle.closed => 'Closed',
    LookingForLifecycle.fulfilled => 'Fulfilled',
    LookingForLifecycle.deleted => 'Deleted',
  };
}

String lookingForRestrictionMessage(DateTime restrictedUntil) {
  final clock = DateFormat('MMM d, h:mm a').format(restrictedUntil.toLocal());
  return "You can't post Looking For requests until $clock.";
}

const List<({String value, String label})> lookingForReportReasons = [
  (value: 'spam', label: 'Spam'),
  (value: 'unrelated_content', label: 'Unrelated content'),
  (value: 'inappropriate_content', label: 'Inappropriate content'),
  (value: 'scam_or_suspicious', label: 'Scam / Suspicious'),
  (value: 'other', label: 'Other'),
];

String? lookingForReportReasonLabel(String value) {
  for (final reason in lookingForReportReasons) {
    if (reason.value == value) return reason.label;
  }
  return null;
}

extension LookingForLifecycleView on LookingForModel {
  DateTime get clock => observedAt ?? DateTime.now().toUtc();

  LookingForLifecycle get lifecycle => classifyLookingFor(
    status: switch (status) {
      LookingForStatus.fulfilled => 'fulfilled',
      LookingForStatus.closed => 'closed',
      LookingForStatus.active => 'open',
    },
    expiresAt: expiresAt,
    serverNow: clock,
    moderationRemovedAt: moderationRemovedAt,
    ownerDeletedAt: ownerDeletedAt,
  );

  bool get showInBrowse => lookingForVisibleInBrowse(lifecycle);
  bool get showInMyActive => lookingForVisibleInMyActive(lifecycle);
  bool get showInInactive => lookingForVisibleInInactive(lifecycle);
  bool get canRepost => lookingForCanRepost(lifecycle);
  bool get canDelete => lookingForCanDelete(lifecycle);
  bool get canEdit => lookingForCanEdit(lifecycle);

  String get lifecycleLabel => lookingForLifecycleLabel(
    lifecycle,
    expiresAt: expiresAt,
    serverNow: clock,
  );
}

String? lookingForReportDetailsError({
  required String reason,
  required String details,
}) {
  final text = details.trim();
  if (reason == 'other') {
    if (text.length < 8) {
      return 'Add a short explanation for Other.';
    }
  }
  if (text.length > lookingForReportDetailsMax) {
    return 'Keep the explanation under $lookingForReportDetailsMax characters.';
  }
  return null;
}
