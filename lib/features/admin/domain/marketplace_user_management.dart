/// Marketplace user directory rules for Admin → Users.
///
/// Stored statuses stay the database values. `suspended` is the administrative
/// disable and is labeled Disabled. `banned` remains the permanent restriction.
const List<String> marketplaceDisableReasons = [
  'Violation of marketplace guidelines',
  'Fraudulent or suspicious activity',
  'Repeated abusive behavior',
  'Multiple confirmed reports',
  'Account security concerns',
  'Other policy violation',
];

/// Roles returned by `list_marketplace_users`. Administrators are excluded
/// in that function and must not be treated as marketplace accounts here.
bool marketplaceRoleIsListed(String role) {
  switch (role.trim().toLowerCase()) {
    case 'buyer':
    case 'seller':
      return true;
    default:
      return false;
  }
}

/// `buyer_seller` means the same person can use Buyer and Seller mode.
/// That comes from `users.role = seller` or an approved seller profile.
String marketplaceAccountTypeLabel(String accountType) {
  switch (accountType.trim().toLowerCase()) {
    case 'buyer_seller':
      return 'Buyer & Seller';
    case 'seller':
      return 'Seller';
    case 'buyer':
      return 'Buyer';
    default:
      return 'Buyer';
  }
}

/// Admin-facing status: trust class Banned is shown as Banned even before sync.
String marketplaceEffectiveAccountStatus({
  required String accountStatus,
  String? trustLevel,
}) {
  final stored = accountStatus.trim().toLowerCase();
  if (stored == 'banned' || trustLevel?.trim() == 'Banned') {
    return 'banned';
  }
  return stored.isEmpty ? 'active' : stored;
}

String marketplaceAccountStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'active':
      return 'Active';
    case 'suspended':
      return 'Disabled';
    case 'banned':
      return 'Banned';
    case 'deactivated':
      return 'Deactivated';
    default:
      final value = status.trim();
      if (value.isEmpty) return 'Unknown';
      return value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
  }
}

String marketplaceVerificationLabel(String? status) {
  switch (status?.trim().toLowerCase()) {
    case 'approved':
      return 'Approved';
    case 'pending':
      return 'Pending review';
    case 'rejected':
      return 'Rejected';
    case null:
    case '':
      return 'Not submitted';
    default:
      return marketplaceAccountStatusLabel(status!);
  }
}

bool canDisableMarketplaceAccount({
  required String role,
  required String accountStatus,
  String? trustLevel,
}) {
  if (!marketplaceRoleIsListed(role)) return false;
  if (trustLevel?.trim() == 'Banned') return false;
  return accountStatus.trim().toLowerCase() == 'active';
}

/// Why Disable is unavailable. Null when the account can be disabled.
String? marketplaceDisableBlockedMessage({
  required String role,
  required String accountStatus,
  String? trustLevel,
}) {
  if (!marketplaceRoleIsListed(role)) {
    return 'Administrator accounts are managed separately.';
  }
  if (trustLevel?.trim() == 'Banned') {
    return 'Account banned. This account is already restricted.';
  }
  switch (accountStatus.trim().toLowerCase()) {
    case 'active':
      return null;
    case 'suspended':
      return 'Account already disabled. No further disabling action is available.';
    case 'banned':
      return 'Account banned. This account is already restricted.';
    case 'deactivated':
      return 'This account is deactivated. No further disabling action is available.';
    default:
      return 'This account is already restricted.';
  }
}

/// Account-type filters for Admin → Users (mutually exclusive buckets).
bool marketplaceAccountMatchesTypeFilter({
  required String accountType,
  String? filter,
}) {
  final value = filter?.trim().toLowerCase();
  if (value == null || value.isEmpty || value == 'all') return true;
  final type = accountType.trim().toLowerCase();
  if (value == 'buyer') return type == 'buyer';
  if (value == 'both') return type == 'buyer_seller';
  return false;
}

bool marketplaceAccountMatchesStatusFilter({
  required String accountStatus,
  String? filter,
}) {
  final value = filter?.trim().toLowerCase();
  if (value == null || value.isEmpty || value == 'all') return true;
  return accountStatus.trim().toLowerCase() == value;
}

bool marketplaceAccountMatchesSearch({
  required String fullName,
  required String email,
  required String username,
  required String search,
}) {
  final term = search.trim().toLowerCase();
  if (term.isEmpty) return true;
  return fullName.toLowerCase().contains(term) ||
      email.toLowerCase().contains(term) ||
      username.toLowerCase().contains(term);
}

bool marketplaceDisableReasonAllowed(String reason) {
  return marketplaceDisableReasons.contains(reason.trim());
}
