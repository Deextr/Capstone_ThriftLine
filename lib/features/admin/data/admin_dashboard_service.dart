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

  Future<AdminMarketplaceSnapshot> loadMarketplace({
    required AdminDashboardPeriod period,
  }) async {
    final map = await _rpc(
      from: period.from,
      to: period.toExclusive,
      compareFrom: period.requestsComparison ? period.compareFrom : null,
      compareTo: period.requestsComparison ? period.compareTo : null,
      bucket: period.bucketParam,
    );
    final snapshot = AdminMarketplaceSnapshot.fromJson(map);
    await _cacheSnapshot(map);
    return snapshot;
  }

  /// Analytical reports still read the legacy snapshot fields.
  Future<AdminDashboardSnapshot> loadSnapshot({
    required AdminDateWindow window,
  }) async {
    final map = await _rpc(from: window.from, to: window.toExclusive);
    return AdminDashboardSnapshot.fromJson(map);
  }

  AdminMarketplaceSnapshot? readCachedMarketplace() {
    final json = _prefs?.adminDashboardCacheJson;
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      final map = supabaseRpcMap(decoded);
      if (map == null || map['kpis'] is! Map) return null;
      return AdminMarketplaceSnapshot.fromJson(map);
    } catch (e) {
      debugPrint('AdminDashboardService cache parse error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _rpc({
    DateTime? from,
    required DateTime to,
    DateTime? compareFrom,
    DateTime? compareTo,
    String? bucket,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_dashboard_snapshot',
      params: {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
        'p_compare_from': compareFrom?.toUtc().toIso8601String(),
        'p_compare_to': compareTo?.toUtc().toIso8601String(),
        'p_bucket': bucket,
      },
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] == false) {
      throw StateError(
        supabaseRpcError(map, fallback: 'Unable to load the dashboard.') ??
            'Unable to load the dashboard.',
      );
    }
    return map;
  }

  Future<void> _cacheSnapshot(Map<String, dynamic> json) async {
    try {
      await _prefs?.setAdminDashboardCacheJson(jsonEncode(json));
    } catch (e) {
      debugPrint('AdminDashboardService cache write error: $e');
    }
  }
}
