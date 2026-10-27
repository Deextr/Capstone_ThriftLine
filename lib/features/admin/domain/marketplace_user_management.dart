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

/// Admin UI copy for [marketplaceDisableReasons]. API / audit values stay in
/// [MarketplaceDisableReasonOption.value].
class MarketplaceDisableReasonOption {
  const MarketplaceDisableReasonOption({
    required this.value,
    required this.title,
    required this.description,
  });

  final String value;
  final String title;
  final String description;
}

const List<MarketplaceDisableReasonOption> marketplaceDisableReasonOptions = [
  MarketplaceDisableReasonOption(
    value: 'Violation of marketplace guidelines',
    title: 'Guidelines violation',
    description: 'Listings, bids, or messages broke marketplace rules.',
  ),
  MarketplaceDisableReasonOption(
    value: 'Fraudulent or suspicious activity',
    title: 'Fraud or suspicious activity',
    description: 'Payment, identity, or listing patterns look high-risk.',
  ),
  MarketplaceDisableReasonOption(
    value: 'Repeated abusive behavior',
    title: 'Repeated abuse',
    description: 'Harassment, threats, or hostile conduct toward others.',
  ),
  MarketplaceDisableReasonOption(
    value: 'Multiple confirmed reports',
    title: 'Confirmed reports',
    description: 'Several community or order reports were upheld.',
  ),
  MarketplaceDisableReasonOption(
    value: 'Account security concerns',
    title: 'Security concern',
    description: 'Possible compromise, takeover, or unsafe account access.',
  ),
  MarketplaceDisableReasonOption(
    value: 'Other policy violation',
    title: 'Other policy issue',
    description: 'Another rule breach that does not fit the categories above.',
  ),
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
    case 'invited':
      return 'Invited';
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

bool canEnableMarketplaceAccount({
  required String role,
  required String accountStatus,
  String? trustLevel,
  bool permanentlySanctioned = false,
}) {
  if (!marketplaceRoleIsListed(role)) return false;
  if (permanentlySanctioned) return false;
  if (trustLevel?.trim() == 'Banned') return false;
  if (accountStatus.trim().toLowerCase() == 'banned') return false;
  return accountStatus.trim().toLowerCase() == 'suspended';
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

/// Why Enable is unavailable. Null when the account can be re-enabled.
String? marketplaceEnableBlockedMessage({
  required String role,
  required String accountStatus,
  String? trustLevel,
  bool permanentlySanctioned = false,
}) {
  if (!marketplaceRoleIsListed(role)) {
    return 'Administrator accounts are managed separately.';
  }
  if (accountStatus.trim().toLowerCase() == 'banned' ||
      trustLevel?.trim() == 'Banned' ||
      permanentlySanctioned) {
    return 'Account banned. Reactivation is not available through User Management.';
  }
  switch (accountStatus.trim().toLowerCase()) {
    case 'suspended':
      return null;
    case 'active':
      return 'This account is already active.';
    case 'deactivated':
      return 'This account is deactivated and cannot be re-enabled here.';
    default:
      return 'This account cannot be re-enabled through User Management.';
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
