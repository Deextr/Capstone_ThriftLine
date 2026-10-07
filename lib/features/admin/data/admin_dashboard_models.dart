import '../../../core/utils/formatters.dart';
import '../../../models/enums.dart';
import '../../trust_safety/data/report_reasons.dart';
import 'admin_review_rules.dart';

enum AdminDatePreset {
  today,
  last7Days,
  last30Days,
  thisMonth,
  lastYear,
  custom,
}

String adminDatePresetLabel(AdminDatePreset preset) => switch (preset) {
  AdminDatePreset.today => 'Today',
  AdminDatePreset.last7Days => 'Last 7 Days',
  AdminDatePreset.last30Days => 'Last 30 Days',
  AdminDatePreset.thisMonth => 'This Month',
  AdminDatePreset.lastYear => 'Last Year',
  AdminDatePreset.custom => 'Custom Range',
};

String adminDatePresetSegmentLabel(AdminDatePreset preset) => switch (preset) {
  AdminDatePreset.today => 'Today',
  AdminDatePreset.last7Days => '7 Days',
  AdminDatePreset.last30Days => '30 Days',
  AdminDatePreset.thisMonth => 'This Month',
  AdminDatePreset.lastYear => '1 Year',
  AdminDatePreset.custom => 'Custom',
};

class AdminDateWindow {
  const AdminDateWindow({
    required this.preset,
    required this.from,
    required this.toExclusive,
  });

  final AdminDatePreset preset;
  final DateTime from;
  final DateTime toExclusive;

  factory AdminDateWindow.today([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final start = DateTime(clock.year, clock.month, clock.day);
    return AdminDateWindow(
      preset: AdminDatePreset.today,
      from: start,
      toExclusive: start.add(const Duration(days: 1)),
    );
  }

  factory AdminDateWindow.last7Days([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    return AdminDateWindow(
      preset: AdminDatePreset.last7Days,
      from: today.subtract(const Duration(days: 6)),
      toExclusive: today.add(const Duration(days: 1)),
    );
  }

  factory AdminDateWindow.last30Days([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    return AdminDateWindow(
      preset: AdminDatePreset.last30Days,
      from: today.subtract(const Duration(days: 29)),
      toExclusive: today.add(const Duration(days: 1)),
    );
  }

  factory AdminDateWindow.thisMonth([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final start = DateTime(clock.year, clock.month, 1);
    final nextMonth = clock.month == 12
        ? DateTime(clock.year + 1, 1, 1)
        : DateTime(clock.year, clock.month + 1, 1);
    return AdminDateWindow(
      preset: AdminDatePreset.thisMonth,
      from: start,
      toExclusive: nextMonth,
    );
  }

  factory AdminDateWindow.lastYear([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final from = DateTime(clock.year - 1, 1, 1);
    return AdminDateWindow(
      preset: AdminDatePreset.lastYear,
      from: from,
      toExclusive: DateTime(clock.year, 1, 1),
    );
  }

  factory AdminDateWindow.custom({
    required DateTime start,
    required DateTime end,
  }) {
    final from = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return AdminDateWindow(
      preset: AdminDatePreset.custom,
      from: from,
      toExclusive: endDay.add(const Duration(days: 1)),
    );
  }

  String get chipLabel {
    if (preset != AdminDatePreset.custom) {
      return adminDatePresetLabel(preset);
    }
    return '${formatFullDate(from)} – ${formatFullDate(toExclusive.subtract(const Duration(seconds: 1)))}';
  }
}

enum AdminDashboardReportFilter { all, underReview, reviewed }

enum AdminDashboardVerificationFilter { pending, approved, rejected }

String adminDashboardReportFilterLabel(AdminDashboardReportFilter filter) =>
    switch (filter) {
      AdminDashboardReportFilter.all => 'All',
      AdminDashboardReportFilter.underReview => 'Under Review',
      AdminDashboardReportFilter.reviewed => 'Reviewed',
    };

String adminDashboardVerificationFilterLabel(
  AdminDashboardVerificationFilter filter,
) => switch (filter) {
  AdminDashboardVerificationFilter.pending => 'Pending',
  AdminDashboardVerificationFilter.approved => 'Approved',
  AdminDashboardVerificationFilter.rejected => 'Rejected',
};

bool isAdminDashboardOfflineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('host lookup') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('offline') ||
      text.contains('timed out') ||
      text.contains('failed host');
}

class AdminDashboardCounts {
  const AdminDashboardCounts({
    required this.registeredInPeriod,
    required this.activeInPeriod,
    required this.activeNow,
    required this.totalUsers,
    required this.pendingVerifications,
    required this.verificationsSubmitted,
    required this.openReports,
    required this.reportsSubmitted,
    required this.ordersPlaced,
    required this.openDisputes,
    required this.grossMarketplaceSales,
    required this.platformRevenue,
  });

  final int registeredInPeriod;
  final int activeInPeriod;
  final int activeNow;
  final int totalUsers;
  final int pendingVerifications;
  final int verificationsSubmitted;
  final int openReports;
  final int reportsSubmitted;
  final int ordersPlaced;
  final int openDisputes;
  final double grossMarketplaceSales;
  final double platformRevenue;

  factory AdminDashboardCounts.fromJson(Map<String, dynamic>? json) {
    return AdminDashboardCounts(
      registeredInPeriod: _asInt(json?['period_users']),
      activeInPeriod: _asInt(json?['period_active'] ?? json?['active_users']),
      activeNow: _asInt(json?['active_now'] ?? json?['active_users']),
      totalUsers: _asInt(json?['total_users']),
      pendingVerifications: _asInt(json?['pending_verifications']),
      verificationsSubmitted: _asInt(json?['period_verifications']),
      openReports: _asInt(json?['open_reports']),
      reportsSubmitted: _asInt(json?['period_reports']),
      ordersPlaced: _asInt(json?['period_orders']),
      openDisputes: _asInt(json?['open_disputes']),
      grossMarketplaceSales: _asDouble(json?['gross_marketplace_sales']),
      platformRevenue: _asDouble(json?['platform_revenue']),
    );
  }
}

class AdminDashboardSalesPoint {
  const AdminDashboardSalesPoint({
    required this.day,
    required this.gross,
    required this.platformRevenue,
  });

  final DateTime day;
  final double gross;
  final double platformRevenue;

  factory AdminDashboardSalesPoint.fromJson(Map<String, dynamic> json) {
    return AdminDashboardSalesPoint(
      day: _asDate(json['day']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      gross: _asDouble(json['gross']),
      platformRevenue: _asDouble(json['platform_revenue']),
    );
  }
}

class AdminDashboardPoint {
  const AdminDashboardPoint({required this.day, required this.count});

  final DateTime day;
  final int count;

  factory AdminDashboardPoint.fromJson(Map<String, dynamic> json) {
    return AdminDashboardPoint(
      day: _asDate(json['day']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      count: _asInt(json['count']),
    );
  }
}

class AdminDashboardStatusCount {
  const AdminDashboardStatusCount({required this.status, required this.count});

  final String status;
  final int count;

  factory AdminDashboardStatusCount.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStatusCount(
      status: (json['status'] as String?)?.trim() ?? '',
      count: _asInt(json['count']),
    );
  }
}

class AdminDashboardVerification {
  const AdminDashboardVerification({
    required this.id,
    required this.applicantName,
    required this.shopName,
    required this.submittedAt,
    required this.status,
  });

  final String id;
  final String applicantName;
  final String shopName;
  final DateTime submittedAt;
  final String status;

  factory AdminDashboardVerification.fromJson(Map<String, dynamic> json) {
    return AdminDashboardVerification(
      id: json['id'] as String? ?? '',
      applicantName:
          (json['applicant_name'] as String?)?.trim().isNotEmpty == true
          ? (json['applicant_name'] as String).trim()
          : 'Applicant',
      shopName: (json['shop_name'] as String?)?.trim().isNotEmpty == true
          ? (json['shop_name'] as String).trim()
          : 'Shop',
      submittedAt: _asDate(json['submitted_at']) ?? DateTime.now(),
      status: (json['status'] as String?)?.trim() ?? 'pending',
    );
  }
}

class AdminDashboardReport {
  const AdminDashboardReport({
    required this.id,
    required this.reporterName,
    required this.reportedName,
    this.reporterRole,
    this.reportedRole,
    required this.category,
    this.orderNumber,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String reporterName;
  final String reportedName;
  final String? reporterRole;
  final String? reportedRole;
  final String category;
  final String? orderNumber;
  final DateTime createdAt;
  final String status;

  String get reasonLabel => reportReasonLabel(category);
  String get roleLabel => accountRoleLabel(reportedRole);
  String get reporterRoleLabel => accountRoleLabel(reporterRole);

  factory AdminDashboardReport.fromJson(Map<String, dynamic> json) {
    final order = (json['order_number'] as String?)?.trim();
    final role = (json['reported_role'] as String?)?.trim();
    final reporterRole = (json['reporter_role'] as String?)?.trim();
    return AdminDashboardReport(
      id: json['id'] as String? ?? '',
      reporterName:
          (json['reporter_name'] as String?)?.trim().isNotEmpty == true
          ? (json['reporter_name'] as String).trim()
          : 'Member',
      reportedName:
          (json['reported_name'] as String?)?.trim().isNotEmpty == true
          ? (json['reported_name'] as String).trim()
          : 'Member',
      reporterRole: (reporterRole == null || reporterRole.isEmpty)
          ? null
          : reporterRole,
      reportedRole: (role == null || role.isEmpty) ? null : role,
      category: (json['category'] as String?)?.trim() ?? '',
      orderNumber: (order == null || order.isEmpty) ? null : order,
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      status: (json['status'] as String?)?.trim() ?? kAdminReportOpenStatus,
    );
  }
}

class AdminDashboardOrder {
  const AdminDashboardOrder({
    required this.orderNumber,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
  });

  final String orderNumber;
  final String status;
  final double totalAmount;
  final DateTime createdAt;

  String get statusLabel => orderStatusLabel(orderStatusFromDb(status));
  String get amountLabel => formatCurrency(totalAmount);

  factory AdminDashboardOrder.fromJson(Map<String, dynamic> json) {
    return AdminDashboardOrder(
      orderNumber: (json['order_number'] as String?)?.trim() ?? 'Order',
      status: (json['status'] as String?)?.trim() ?? 'pending',
      totalAmount: _asDouble(json['total_amount']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class AdminDashboardSnapshot {
  const AdminDashboardSnapshot({
    required this.generatedAt,
    required this.bucket,
    required this.counts,
    required this.registrations,
    required this.ordersByDay,
    required this.ordersByStatus,
    required this.reportsByDay,
    required this.reportsByStatus,
    required this.salesRevenueSeries,
    required this.pendingVerifications,
    required this.recentReports,
    required this.recentOrders,
  });

  final DateTime generatedAt;
  final String bucket;
  final AdminDashboardCounts counts;
  final List<AdminDashboardPoint> registrations;
  final List<AdminDashboardPoint> ordersByDay;
  final List<AdminDashboardStatusCount> ordersByStatus;
  final List<AdminDashboardPoint> reportsByDay;
  final List<AdminDashboardStatusCount> reportsByStatus;
  final List<AdminDashboardVerification> pendingVerifications;
  final List<AdminDashboardSalesPoint> salesRevenueSeries;
  final List<AdminDashboardReport> recentReports;
  final List<AdminDashboardOrder> recentOrders;

  int get registrationTotal =>
      registrations.fold<int>(0, (sum, point) => sum + point.count);

  int get orderTotal =>
      ordersByDay.fold<int>(0, (sum, point) => sum + point.count);

  int get reportTotal =>
      reportsByDay.fold<int>(0, (sum, point) => sum + point.count);

  factory AdminDashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return AdminDashboardSnapshot(
      generatedAt: _asDate(json['generated_at']) ?? DateTime.now(),
      bucket: (json['bucket'] as String?) ?? 'day',
      counts: AdminDashboardCounts.fromJson(
        json['counts'] is Map<String, dynamic>
            ? json['counts'] as Map<String, dynamic>
            : json['counts'] is Map
            ? Map<String, dynamic>.from(json['counts'] as Map)
            : null,
      ),
      registrations: _mapList(
        json['registrations'],
        AdminDashboardPoint.fromJson,
      ),
      ordersByDay: _mapList(
        json['orders_by_day'],
        AdminDashboardPoint.fromJson,
      ),
      ordersByStatus: _mapList(
        json['orders_by_status'],
        AdminDashboardStatusCount.fromJson,
      ),
      reportsByDay: _mapList(
        json['reports_by_day'],
        AdminDashboardPoint.fromJson,
      ),
      reportsByStatus: _mapList(
        json['reports_by_status'],
        AdminDashboardStatusCount.fromJson,
      ),
      salesRevenueSeries: _mapList(
        json['sales_revenue_series'],
        AdminDashboardSalesPoint.fromJson,
      ),
      pendingVerifications: _mapList(
        json['pending_verifications'],
        AdminDashboardVerification.fromJson,
      ),
      recentReports: _mapList(
        json['recent_reports'],
        AdminDashboardReport.fromJson,
      ),
      recentOrders: _mapList(
        json['recent_orders'],
        AdminDashboardOrder.fromJson,
      ),
    );
  }
}

List<AdminDashboardReport> filterDashboardReports(
  List<AdminDashboardReport> reports,
  AdminDashboardReportFilter filter,
) {
  return switch (filter) {
    AdminDashboardReportFilter.all => reports,
    AdminDashboardReportFilter.underReview =>
      reports.where((item) => item.status == kAdminReportOpenStatus).toList(),
    AdminDashboardReportFilter.reviewed =>
      reports.where((item) => item.status != kAdminReportOpenStatus).toList(),
  };
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<T> _mapList<T>(Object? value, T Function(Map<String, dynamic> json) map) {
  if (value is! List) return <T>[];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        map(item)
      else if (item is Map)
        map(Map<String, dynamic>.from(item)),
  ];
}
