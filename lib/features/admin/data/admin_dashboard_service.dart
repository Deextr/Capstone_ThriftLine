import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../domain/admin_dashboard_period.dart';
import 'admin_dashboard_models.dart';
import 'admin_marketplace_dashboard.dart';

class AdminDashboardService {
  AdminDashboardService(this._supabase, {SharedPreferencesService? prefs})
    : _prefs = prefs;

  final SupabaseService _supabase;
  final SharedPreferencesService? _prefs;

  static const _cachePeriodKeyField = 'cache_period_key';

  Future<AdminMarketplaceSnapshot> loadMarketplace({
    required AdminDashboardPeriod period,
  }) async {
    final map = await _rpc(
      period: period,
      from: period.from,
      to: period.toExclusive,
      compareFrom: period.requestsComparison ? period.compareFrom : null,
      compareTo: period.requestsComparison ? period.compareTo : null,
      bucket: period.bucketParam,
    );
    final snapshot = AdminMarketplaceSnapshot.fromJson(map);
    var overdue = snapshot.activity.ordersOverdueFulfillment;
    try {
      final raw = await _supabase.adminQuery(
        (client) => client.rpc('fulfillment_overdue_count'),
      );
      if (raw is int) {
        overdue = raw;
      } else if (raw is num) {
        overdue = raw.toInt();
      }
    } catch (e) {
      debugPrint('fulfillment_overdue_count error: $e');
    }
    final merged = AdminMarketplaceSnapshot(
      generatedAt: snapshot.generatedAt,
      bucket: snapshot.bucket,
      comparisonAvailable: snapshot.comparisonAvailable,
      kpis: snapshot.kpis,
      activity: snapshot.activity.copyWith(ordersOverdueFulfillment: overdue),
      attention: snapshot.attention,
      revenueSeries: snapshot.revenueSeries,
      recentActivity: snapshot.recentActivity,
    );
    await _cacheSnapshot(period, _marketplaceCachePayload(map, overdue));
    return merged;
  }

  /// Analytical reports still read the legacy snapshot fields.
  Future<AdminDashboardSnapshot> loadSnapshot({
    required AdminDateWindow window,
  }) async {
    final map = await _rpc(
      from: window.from,
      to: window.toExclusive,
    );
    return AdminDashboardSnapshot.fromJson(map);
  }

  AdminMarketplaceSnapshot? readCachedMarketplace(AdminDashboardPeriod period) {
    final json = _prefs?.adminDashboardCacheJson;
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      final map = supabaseRpcMap(decoded);
      if (map == null || map['kpis'] is! Map) return null;
      final cachedKey = map[_cachePeriodKeyField]?.toString();
      if (cachedKey != null && cachedKey != period.cacheKey) {
        return null;
      }
      return AdminMarketplaceSnapshot.fromJson(map);
    } catch (e) {
      debugPrint('AdminDashboardService cache parse error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _rpc({
    AdminDashboardPeriod? period,
    DateTime? from,
    required DateTime to,
    DateTime? compareFrom,
    DateTime? compareTo,
    String? bucket,
  }) async {
    final raw = await _supabase.adminQuery(
      (client) => client.rpc(
        'admin_dashboard_snapshot',
        params: {
          'p_from': from?.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
          'p_compare_from': compareFrom?.toUtc().toIso8601String(),
          'p_compare_to': compareTo?.toUtc().toIso8601String(),
          'p_bucket': bucket,
        },
      ),
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] == false) {
      throw StateError(
        supabaseRpcError(map, fallback: 'Unable to load the dashboard.') ??
            'Unable to load the dashboard.',
      );
    }
    if (period != null) {
      map[_cachePeriodKeyField] = period.cacheKey;
    }
    return map;
  }

  @visibleForTesting
  static Map<String, dynamic> marketplaceCachePayload(
    Map<String, dynamic> rpcMap,
    int ordersOverdueFulfillment,
  ) => _marketplaceCachePayload(rpcMap, ordersOverdueFulfillment);

  static Map<String, dynamic> _marketplaceCachePayload(
    Map<String, dynamic> rpcMap,
    int ordersOverdueFulfillment,
  ) {
    final cache = Map<String, dynamic>.from(rpcMap);
    final activityRaw = cache['activity'];
    final activity = activityRaw is Map
        ? Map<String, dynamic>.from(activityRaw)
        : <String, dynamic>{};
    activity['orders_overdue_fulfillment'] = ordersOverdueFulfillment;
    cache['activity'] = activity;
    return cache;
  }

  Future<void> _cacheSnapshot(
    AdminDashboardPeriod period,
    Map<String, dynamic> json,
  ) async {
    try {
      final payload = Map<String, dynamic>.from(json)
        ..[_cachePeriodKeyField] = period.cacheKey;
      await _prefs?.setAdminDashboardCacheJson(jsonEncode(payload));
    } catch (e) {
      debugPrint('AdminDashboardService cache write error: $e');
    }
  }
}
