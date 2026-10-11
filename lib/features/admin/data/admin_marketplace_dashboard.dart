import '../domain/admin_dashboard_period.dart';

class AdminDashboardKpis {
  const AdminDashboardKpis({
    required this.newUsers,
    required this.newUsersPrevious,
    required this.completedOrders,
    required this.completedOrdersPrevious,
    required this.platformRevenue,
    required this.platformRevenuePrevious,
    required this.paidOrders,
    required this.paidOrdersPrevious,
  });

  final int newUsers;
  final int? newUsersPrevious;
  final int completedOrders;
  final int? completedOrdersPrevious;
  final double platformRevenue;
  final double? platformRevenuePrevious;
  final int paidOrders;
  final int? paidOrdersPrevious;

  factory AdminDashboardKpis.fromJson(Map<String, dynamic> json) {
    return AdminDashboardKpis(
      newUsers: _requiredInt(json['new_users']),
      newUsersPrevious: _optionalInt(json['new_users_previous']),
      completedOrders: _requiredInt(json['completed_orders']),
      completedOrdersPrevious: _optionalInt(json['completed_orders_previous']),
      platformRevenue: _requiredDouble(json['platform_revenue']),
      platformRevenuePrevious: _optionalDouble(
        json['platform_revenue_previous'],
      ),
      paidOrders: _requiredInt(json['paid_orders']),
      paidOrdersPrevious: _optionalInt(json['paid_orders_previous']),
    );
  }
}

class AdminDashboardActivity {
  const AdminDashboardActivity({
    required this.newListings,
    required this.sellerApplications,
    required this.paidAuctionOrders,
    required this.ordersAwaitingFulfillment,
  });

  final int newListings;
  final int sellerApplications;
  final int paidAuctionOrders;
  final int ordersAwaitingFulfillment;

  factory AdminDashboardActivity.fromJson(Map<String, dynamic>? json) {
    return AdminDashboardActivity(
      newListings: _requiredInt(json?['new_listings']),
      sellerApplications: _requiredInt(json?['seller_applications']),
      paidAuctionOrders: _requiredInt(json?['paid_auction_orders']),
      ordersAwaitingFulfillment: _requiredInt(
        json?['orders_awaiting_fulfillment'],
      ),
    );
  }
}

class AdminDashboardAttention {
  const AdminDashboardAttention({
    required this.pendingVerifications,
    required this.openCommunityDisputes,
    required this.openOrderDisputes,
    required this.openLookingForDisputes,
    required this.activeBiddingRestrictions,
    required this.paymentReviews,
  });

  final int pendingVerifications;
  final int openCommunityDisputes;
  final int openOrderDisputes;
  final int openLookingForDisputes;
  final int activeBiddingRestrictions;
  final int paymentReviews;

  int get openDisputes =>
      openCommunityDisputes + openOrderDisputes + openLookingForDisputes;

  factory AdminDashboardAttention.fromJson(Map<String, dynamic>? json) {
    return AdminDashboardAttention(
      pendingVerifications: _requiredInt(json?['pending_verifications']),
      openCommunityDisputes: _requiredInt(json?['open_community_disputes']),
      openOrderDisputes: _requiredInt(json?['open_order_disputes']),
      openLookingForDisputes: _requiredInt(json?['open_looking_for_disputes']),
      activeBiddingRestrictions: _requiredInt(
        json?['active_bidding_restrictions'],
      ),
      paymentReviews: _requiredInt(json?['payment_reviews']),
    );
  }
}

class AdminRevenuePoint {
  const AdminRevenuePoint({
    required this.at,
    required this.current,
    required this.previous,
  });

  final DateTime at;
  final double current;
  final double? previous;

  factory AdminRevenuePoint.fromJson(Map<String, dynamic> json) {
    final at = _asDate(json['at']);
    if (at == null) {
      throw const FormatException('Revenue point is missing a timestamp.');
    }
    return AdminRevenuePoint(
      at: at,
      current: _requiredDouble(json['current']),
      previous: _optionalDouble(json['previous']),
    );
  }
}

class AdminRecentActivity {
  const AdminRecentActivity({
    required this.kind,
    required this.occurredAt,
    required this.title,
    required this.detail,
    required this.actor,
    required this.targetType,
    required this.targetId,
  });

  final String kind;
  final DateTime occurredAt;
  final String title;
  final String detail;
  final String actor;
  final String targetType;
  final String targetId;

  bool get isAdminAction => actor == 'admin';

  factory AdminRecentActivity.fromJson(Map<String, dynamic> json) {
    final at = _asDate(json['occurred_at']);
    if (at == null) {
      throw const FormatException('Activity is missing a timestamp.');
    }
    return AdminRecentActivity(
      kind: (json['kind'] as String?)?.trim() ?? '',
      occurredAt: at,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Marketplace activity',
      detail: (json['detail'] as String?)?.trim() ?? '',
      actor: (json['actor'] as String?)?.trim() ?? 'member',
      targetType: (json['target_type'] as String?)?.trim() ?? '',
      targetId: (json['target_id'] as String?)?.trim() ?? '',
    );
  }
}

class AdminMarketplaceSnapshot {
  const AdminMarketplaceSnapshot({
    required this.generatedAt,
    required this.bucket,
    required this.comparisonAvailable,
    required this.kpis,
    required this.activity,
    required this.attention,
    required this.revenueSeries,
    required this.recentActivity,
  });

  final DateTime generatedAt;
  final AdminDashboardBucket bucket;
  final bool comparisonAvailable;
  final AdminDashboardKpis kpis;
  final AdminDashboardActivity activity;
  final AdminDashboardAttention attention;
  final List<AdminRevenuePoint> revenueSeries;
  final List<AdminRecentActivity> recentActivity;

  bool get hasRevenue {
    for (final point in revenueSeries) {
      if (point.current != 0) return true;
      final previous = point.previous;
      if (previous != null && previous != 0) return true;
    }
    return false;
  }

  factory AdminMarketplaceSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['kpis'] is! Map) {
      throw const FormatException('Dashboard metrics were missing.');
    }
    return AdminMarketplaceSnapshot(
      generatedAt: _asDate(json['generated_at']) ?? DateTime.now().toUtc(),
      bucket: _bucket(json['bucket']),
      comparisonAvailable: json['comparison_available'] == true,
      kpis: AdminDashboardKpis.fromJson(_map(json['kpis'])),
      activity: AdminDashboardActivity.fromJson(
        json['activity'] is Map ? _map(json['activity']) : null,
      ),
      attention: AdminDashboardAttention.fromJson(
        json['attention'] is Map ? _map(json['attention']) : null,
      ),
      revenueSeries: _mapList(
        json['revenue_series'],
        AdminRevenuePoint.fromJson,
      ),
      recentActivity: _mapList(
        json['recent_activity'],
        AdminRecentActivity.fromJson,
      ),
    );
  }
}

AdminDashboardBucket _bucket(Object? value) => switch (value) {
  'hour' => AdminDashboardBucket.hour,
  'month' => AdminDashboardBucket.month,
  'year' => AdminDashboardBucket.year,
  'auto' => AdminDashboardBucket.auto,
  _ => AdminDashboardBucket.day,
};

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

int _requiredInt(Object? value) {
  final parsed = _optionalInt(value);
  if (parsed == null) {
    throw const FormatException('Dashboard metric was missing.');
  }
  return parsed;
}

double _requiredDouble(Object? value) {
  final parsed = _optionalDouble(value);
  if (parsed == null) {
    throw const FormatException('Dashboard metric was missing.');
  }
  return parsed;
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String && value.trim().isNotEmpty) return int.tryParse(value);
  return null;
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String && value.trim().isNotEmpty) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
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
