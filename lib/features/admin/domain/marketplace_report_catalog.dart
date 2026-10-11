import '../data/admin_dashboard_models.dart';

enum MarketplaceReportCategory {
  overview,
  users,
  orders,
  payments,
  auctions,
  disputes,
  verifications,
  security,
}

String marketplaceReportCategoryLabel(MarketplaceReportCategory category) =>
    switch (category) {
      MarketplaceReportCategory.overview => 'Overview',
      MarketplaceReportCategory.users => 'Users',
      MarketplaceReportCategory.orders => 'Orders & Sales',
      MarketplaceReportCategory.payments => 'Payments & Revenue',
      MarketplaceReportCategory.auctions => 'Auctions',
      MarketplaceReportCategory.disputes => 'Disputes',
      MarketplaceReportCategory.verifications => 'Seller Verifications',
      MarketplaceReportCategory.security => 'Security & Activity',
    };

List<String> adminReportFilterKeys(AdminReportType type) => switch (type) {
      AdminReportType.all => const [],
      AdminReportType.verifications =>
        marketplaceReportFilterKeysFor(MarketplaceReportCategory.verifications),
      AdminReportType.users =>
        marketplaceReportFilterKeysFor(MarketplaceReportCategory.users),
      AdminReportType.ordersTransactions => const [
          'order_type',
          'order_status',
          'seller',
          'payment_status',
        ],
      AdminReportType.bidding =>
        marketplaceReportFilterKeysFor(MarketplaceReportCategory.auctions),
      AdminReportType.disputes =>
        marketplaceReportFilterKeysFor(MarketplaceReportCategory.disputes),
      AdminReportType.security =>
        marketplaceReportFilterKeysFor(MarketplaceReportCategory.security),
    };

/// Filter keys allowed per RPC category.
List<String> marketplaceReportFilterKeysFor(MarketplaceReportCategory category) =>
    switch (category) {
      MarketplaceReportCategory.overview => const [],
      MarketplaceReportCategory.users => const ['account_type', 'account_status'],
      MarketplaceReportCategory.orders => const ['order_type', 'order_status', 'seller'],
      MarketplaceReportCategory.payments => const ['payment_status'],
      MarketplaceReportCategory.auctions => const ['auction_outcome'],
      MarketplaceReportCategory.disputes => const ['dispute_type', 'dispute_status'],
      MarketplaceReportCategory.verifications => const ['verification_outcome'],
      MarketplaceReportCategory.security => const ['event_category'],
    };

String marketplaceReportCategoryRpcValue(MarketplaceReportCategory category) =>
    switch (category) {
      MarketplaceReportCategory.overview => 'overview',
      MarketplaceReportCategory.users => 'users',
      MarketplaceReportCategory.orders => 'orders',
      MarketplaceReportCategory.payments => 'payments',
      MarketplaceReportCategory.auctions => 'auctions',
      MarketplaceReportCategory.disputes => 'disputes',
      MarketplaceReportCategory.verifications => 'verifications',
      MarketplaceReportCategory.security => 'security',
    };

/// The seven report types shown in the Admin Reports module, in display order.
enum AdminReportType {
  all,
  verifications,
  users,
  ordersTransactions,
  bidding,
  disputes,
  security,
}

const adminReportTypesInOrder = AdminReportType.values;

String adminReportTypeLabel(AdminReportType type) => switch (type) {
      AdminReportType.all => 'All Reports',
      AdminReportType.verifications => 'Seller Verification Reports',
      AdminReportType.users => 'Users Reports',
      AdminReportType.ordersTransactions => 'Orders & Transactions Reports',
      AdminReportType.bidding => 'Bidding Reports',
      AdminReportType.disputes => 'Disputes Reports',
      AdminReportType.security => 'Security & Activity Reports',
    };

String adminReportTypeQueryValue(AdminReportType type) => switch (type) {
      AdminReportType.all => 'all',
      AdminReportType.verifications => 'verifications',
      AdminReportType.users => 'users',
      AdminReportType.ordersTransactions => 'orders_transactions',
      AdminReportType.bidding => 'bidding',
      AdminReportType.disputes => 'disputes',
      AdminReportType.security => 'security',
    };

AdminReportType adminReportTypeFromQuery(String? raw) {
  final value = raw?.toLowerCase().trim() ?? '';
  return switch (value) {
    '' || 'all' || 'overview' => AdminReportType.all,
    'verifications' => AdminReportType.verifications,
    'users' => AdminReportType.users,
    'orders' || 'payments' || 'orders_transactions' => AdminReportType.ordersTransactions,
    'auctions' || 'bidding' => AdminReportType.bidding,
    'disputes' => AdminReportType.disputes,
    'security' => AdminReportType.security,
    _ => AdminReportType.all,
  };
}

/// Primary RPC category for a single report type. All Reports uses the bundled RPC.
MarketplaceReportCategory adminReportPrimaryCategory(AdminReportType type) =>
    switch (type) {
      AdminReportType.all => MarketplaceReportCategory.overview,
      AdminReportType.verifications => MarketplaceReportCategory.verifications,
      AdminReportType.users => MarketplaceReportCategory.users,
      AdminReportType.ordersTransactions => MarketplaceReportCategory.orders,
      AdminReportType.bidding => MarketplaceReportCategory.auctions,
      AdminReportType.disputes => MarketplaceReportCategory.disputes,
      AdminReportType.security => MarketplaceReportCategory.security,
    };

/// Ordered sections when All Reports is selected. Payments stay inside orders.
const marketplaceReportAllSectionCategories = [
  MarketplaceReportCategory.verifications,
  MarketplaceReportCategory.users,
  MarketplaceReportCategory.orders,
  MarketplaceReportCategory.payments,
  MarketplaceReportCategory.auctions,
  MarketplaceReportCategory.disputes,
  MarketplaceReportCategory.security,
];

class MarketplaceReportSelection {
  const MarketplaceReportSelection(this.type);

  final AdminReportType type;

  const MarketplaceReportSelection.all() : type = AdminReportType.all;

  bool get isAll => type == AdminReportType.all;
  bool get includesPaymentSection =>
      type == AdminReportType.ordersTransactions || type == AdminReportType.all;

  MarketplaceReportCategory get singleCategory => adminReportPrimaryCategory(type);

  String get queryValue => adminReportTypeQueryValue(type);

  String get label => adminReportTypeLabel(type);

  static MarketplaceReportSelection fromQuery(String? raw) {
    return MarketplaceReportSelection(adminReportTypeFromQuery(raw));
  }
}

MarketplaceReportCategory? marketplaceReportCategoryFromQuery(String? raw) {
  if (raw == null || raw.isEmpty) return MarketplaceReportCategory.overview;
  if (raw.toLowerCase() == 'all') return null;
  return switch (raw.toLowerCase()) {
    'overview' => MarketplaceReportCategory.overview,
    'users' => MarketplaceReportCategory.users,
    'orders' => MarketplaceReportCategory.orders,
    'payments' => MarketplaceReportCategory.payments,
    'auctions' => MarketplaceReportCategory.auctions,
    'disputes' => MarketplaceReportCategory.disputes,
    'verifications' => MarketplaceReportCategory.verifications,
    'security' => MarketplaceReportCategory.security,
    _ => null,
  };
}

enum MarketplaceReportComparisonMode {
  none,
  previousPeriod,
  samePeriodLastYear,
}

String marketplaceReportComparisonLabel(MarketplaceReportComparisonMode mode) =>
    switch (mode) {
      MarketplaceReportComparisonMode.none => 'No comparison',
      MarketplaceReportComparisonMode.previousPeriod => 'Previous period',
      MarketplaceReportComparisonMode.samePeriodLastYear => 'Same period last year',
    };

/// Philippine Time windows for admin marketplace reports (UTC+8, no DST).
class MarketplaceReportDateWindow {
  const MarketplaceReportDateWindow({
    required this.preset,
    required this.from,
    required this.toExclusive,
    this.yearToDate = false,
  });

  final AdminDatePreset preset;
  final DateTime from;
  final DateTime toExclusive;
  final bool yearToDate;

  static const Duration _manilaOffset = Duration(hours: 8);

  static DateTime _manilaNow([DateTime? utcNow]) {
    final utc = (utcNow ?? DateTime.now()).toUtc();
    return utc.add(_manilaOffset);
  }

  static DateTime _startOfManilaDay(DateTime manilaLocal) {
    return DateTime(manilaLocal.year, manilaLocal.month, manilaLocal.day);
  }

  /// UTC instant for start of a Manila calendar day.
  static DateTime _utcFromManilaLocal(DateTime manilaLocal) {
    return manilaLocal.subtract(_manilaOffset).toUtc();
  }

  factory MarketplaceReportDateWindow.today([DateTime? utcNow]) {
    final manila = _manilaNow(utcNow);
    final start = _startOfManilaDay(manila);
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.today,
      from: _utcFromManilaLocal(start),
      toExclusive: _utcFromManilaLocal(start.add(const Duration(days: 1))),
    );
  }

  factory MarketplaceReportDateWindow.last7Days([DateTime? utcNow]) {
    final manila = _manilaNow(utcNow);
    final endDay = _startOfManilaDay(manila).add(const Duration(days: 1));
    final start = endDay.subtract(const Duration(days: 7));
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.last7Days,
      from: _utcFromManilaLocal(start),
      toExclusive: _utcFromManilaLocal(endDay),
    );
  }

  factory MarketplaceReportDateWindow.last30Days([DateTime? utcNow]) {
    final manila = _manilaNow(utcNow);
    final endDay = _startOfManilaDay(manila).add(const Duration(days: 1));
    final start = endDay.subtract(const Duration(days: 30));
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.last30Days,
      from: _utcFromManilaLocal(start),
      toExclusive: _utcFromManilaLocal(endDay),
    );
  }

  factory MarketplaceReportDateWindow.thisMonth([DateTime? utcNow]) {
    final manila = _manilaNow(utcNow);
    final start = DateTime(manila.year, manila.month, 1);
    final endExclusive = DateTime(manila.year, manila.month, manila.day + 1);
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.thisMonth,
      from: _utcFromManilaLocal(start),
      toExclusive: _utcFromManilaLocal(endExclusive),
    );
  }

  factory MarketplaceReportDateWindow.thisYear([DateTime? utcNow]) {
    final manila = _manilaNow(utcNow);
    final start = DateTime(manila.year, 1, 1);
    final endExclusive = DateTime(manila.year, manila.month, manila.day + 1);
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.custom,
      from: _utcFromManilaLocal(start),
      toExclusive: _utcFromManilaLocal(endExclusive),
      yearToDate: true,
    );
  }

  factory MarketplaceReportDateWindow.custom({
    required DateTime startManila,
    required DateTime endManila,
  }) {
    final fromDay = _startOfManilaDay(startManila);
    final endDay = _startOfManilaDay(endManila).add(const Duration(days: 1));
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.custom,
      from: _utcFromManilaLocal(fromDay),
      toExclusive: _utcFromManilaLocal(endDay),
    );
  }

  Duration get elapsed => toExclusive.difference(from);

  String get chipLabel {
    if (yearToDate) return 'Yearly';
    return switch (preset) {
      AdminDatePreset.today => 'Today',
      AdminDatePreset.last7Days => 'Weekly',
      AdminDatePreset.thisMonth => 'Monthly',
      AdminDatePreset.last30Days => 'Monthly',
      AdminDatePreset.custom => AdminDateWindow(
          preset: preset,
          from: from.toLocal(),
          toExclusive: toExclusive.toLocal(),
        ).chipLabel,
      AdminDatePreset.lastYear => 'Yearly',
    };
  }

  /// Value for the Reports module date-range filter dropdown.
  String get reportDateRangeKey {
    if (yearToDate) return 'yearly';
    return switch (preset) {
      AdminDatePreset.today => 'today',
      AdminDatePreset.last7Days => 'weekly',
      AdminDatePreset.thisMonth => 'monthly',
      AdminDatePreset.last30Days => 'monthly',
      AdminDatePreset.custom => 'custom',
      AdminDatePreset.lastYear => 'yearly',
    };
  }

  /// Short label shown on the date-range filter control.
  String get reportDateRangeButtonLabel {
    if (preset == AdminDatePreset.custom && !yearToDate) {
      return chipLabel;
    }
    return chipLabel;
  }

  DateTime get manilaFrom => from.toUtc().add(_manilaOffset);
  DateTime get manilaToExclusive => toExclusive.toUtc().add(_manilaOffset);

  MarketplaceReportDateWindow? comparisonWindow(
    MarketplaceReportComparisonMode mode,
  ) {
    return switch (mode) {
      MarketplaceReportComparisonMode.none => null,
      MarketplaceReportComparisonMode.previousPeriod => _previousEquivalent(),
      MarketplaceReportComparisonMode.samePeriodLastYear => _samePeriodLastYear(),
    };
  }

  MarketplaceReportDateWindow _previousEquivalent() {
    final span = elapsed;
    return MarketplaceReportDateWindow(
      preset: AdminDatePreset.custom,
      from: from.subtract(span),
      toExclusive: from,
    );
  }

  MarketplaceReportDateWindow _samePeriodLastYear() {
    final mf = manilaFrom;
    final mte = manilaToExclusive;
    final prevStart = _shiftYear(mf, -1);
    final prevEnd = _shiftYear(mte, -1);
    return MarketplaceReportDateWindow.custom(
      startManila: prevStart,
      endManila: prevEnd.subtract(const Duration(days: 1)),
    );
  }

  static DateTime _shiftYear(DateTime manila, int deltaYears) {
    var year = manila.year + deltaYears;
    var month = manila.month;
    var day = manila.day;
    if (month == 2 && day == 29) {
      day = 28;
    }
    return DateTime(year, month, day, manila.hour, manila.minute, manila.second);
  }
}

double? marketplaceReportPercentChange(num? current, num? previous) {
  if (previous == null) return null;
  if (previous == 0) return null;
  if (current == null) return null;
  return ((current - previous) / previous) * 100;
}

String formatMarketplaceReportChange(double? pct) {
  if (pct == null) return 'N/A';
  final sign = pct > 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1)}%';
}

/// Prefix cells that could be interpreted as spreadsheet formulas.
String sanitizeSpreadsheetCell(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return value;
  final first = trimmed[0];
  if (first == '=' || first == '+' || first == '-' || first == '@') {
    return "'$value";
  }
  return value;
}

const int marketplaceReportExportDetailCap = 5000;
const int marketplaceReportPageSize = 25;
