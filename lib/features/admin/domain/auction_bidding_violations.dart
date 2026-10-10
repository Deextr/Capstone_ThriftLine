/// Confirmed auction bidding violations (winner non-payment only).
/// Enforcement thresholds match [record_auction_winner_non_payment] in Supabase.
const int kAuctionBiddingViolationBanThreshold = 3;

const String kAuctionNonPaymentViolationType = 'Auction winner non-payment';

/// Server `consequence` values on [auction_bidding_violations].
const String kConsequenceWarning = 'warning';
const String kConsequenceBiddingRestricted = 'bidding_restricted_3_days';
const String kConsequenceAccountDisabled = 'account_disabled';

enum ViolationCountFilter { all, first, second, threeOnly }

enum BiddingRestrictionStatusFilter {
  all,
  active,
  restricted,
  banned,
  needsAttention,
}

String formatOrdinalViolationCount(int count) {
  if (count <= 0) return 'No violations';
  final suffix = switch (count % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (count % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    },
  };
  return '$count$suffix violation';
}

String violationStageLabel(int violationCount) {
  if (violationCount <= 0) return 'No violations';
  if (violationCount == 1) return 'First Violation';
  if (violationCount == 2) return 'Second Violation';
  if (violationCount >= kAuctionBiddingViolationBanThreshold) {
    return 'Penalty Threshold Reached';
  }
  return formatOrdinalViolationCount(violationCount);
}

String consequenceDisplayLabel(String consequence) {
  return switch (consequence.trim()) {
    kConsequenceWarning => 'Warning',
    kConsequenceBiddingRestricted => '3-day bidding restriction',
    kConsequenceAccountDisabled => 'Account disabled (auction non-payment)',
    _ => consequence,
  };
}

/// Bidding eligibility derived from [auction_bidding_sanctions] and account status.
enum BiddingEnforcementStatus { active, restricted, banned }

BiddingEnforcementStatus resolveBiddingEnforcementStatus({
  required DateTime? permanentlyDisabledAt,
  required DateTime? restrictedUntil,
  required String accountStatus,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  if (permanentlyDisabledAt != null) {
    return BiddingEnforcementStatus.banned;
  }
  if (accountStatus.trim().toLowerCase() == 'banned') {
    return BiddingEnforcementStatus.banned;
  }
  if (restrictedUntil != null && restrictedUntil.isAfter(clock)) {
    return BiddingEnforcementStatus.restricted;
  }
  return BiddingEnforcementStatus.active;
}

String biddingEnforcementStatusLabel(BiddingEnforcementStatus status) {
  return switch (status) {
    BiddingEnforcementStatus.active => 'Active',
    BiddingEnforcementStatus.restricted => 'Restricted',
    BiddingEnforcementStatus.banned => 'Banned',
  };
}

/// Human-readable time left on an active bidding restriction (admin UI).
String formatBiddingRestrictionRemaining(
  DateTime restrictedUntil, {
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toLocal();
  final end = restrictedUntil.toLocal();
  final remaining = end.difference(clock);
  if (remaining.inSeconds <= 0) return '';

  if (remaining.inDays > 1) {
    final days = remaining.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} remaining';
  }

  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  final hourLabel = hours == 1 ? 'hour' : 'hours';
  final minuteLabel = minutes == 1 ? 'minute' : 'minutes';

  if (hours <= 0) {
    return '$minutes $minuteLabel remaining';
  }
  if (minutes <= 0) {
    return '$hours $hourLabel remaining';
  }
  return '$hours $hourLabel and $minutes $minuteLabel remaining';
}

bool matchesViolationCountFilter(int count, ViolationCountFilter filter) {
  return switch (filter) {
    ViolationCountFilter.all => true,
    ViolationCountFilter.first => count == 1,
    ViolationCountFilter.second => count == 2,
    ViolationCountFilter.threeOnly =>
      count == kAuctionBiddingViolationBanThreshold,
  };
}

bool matchesBiddingStatusFilter(
  BiddingEnforcementStatus status,
  BiddingRestrictionStatusFilter filter,
) {
  return switch (filter) {
    BiddingRestrictionStatusFilter.all => true,
    BiddingRestrictionStatusFilter.active =>
      status == BiddingEnforcementStatus.active,
    BiddingRestrictionStatusFilter.restricted =>
      status == BiddingEnforcementStatus.restricted,
    BiddingRestrictionStatusFilter.banned =>
      status == BiddingEnforcementStatus.banned,
    BiddingRestrictionStatusFilter.needsAttention =>
      status == BiddingEnforcementStatus.restricted ||
          status == BiddingEnforcementStatus.banned,
  };
}

bool matchesBuyerSearch({
  required String query,
  required String displayName,
  required String email,
  required String username,
  required String userId,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (displayName.toLowerCase().contains(q)) return true;
  if (email.toLowerCase().contains(q)) return true;
  if (username.toLowerCase().contains(q)) return true;
  if (userId.toLowerCase().contains(q)) return true;
  if (username.isNotEmpty && '@$username'.toLowerCase().contains(q)) {
    return true;
  }
  return false;
}
