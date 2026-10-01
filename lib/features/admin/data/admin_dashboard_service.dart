import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import 'admin_dashboard_models.dart';
import 'admin_review_rules.dart';

class AdminDashboardService {
  AdminDashboardService(this._supabase, {SharedPreferencesService? prefs})
    : _prefs = prefs;

  final SupabaseService _supabase;
  final SharedPreferencesService? _prefs;

  Future<AdminDashboardSnapshot> loadSnapshot({
    required AdminDateWindow window,
  }) async {
    try {
      final raw = await _supabase.client.rpc(
        'admin_dashboard_snapshot',
        params: {
          'p_from': window.from.toUtc().toIso8601String(),
          'p_to': window.toExclusive.toUtc().toIso8601String(),
        },
      );
      final map = supabaseRpcMap(raw);
      if (map == null) {
        throw StateError('Unable to load the dashboard.');
      }
      if (map['success'] == false) {
        throw StateError(
          supabaseRpcError(map, fallback: 'Unable to load the dashboard.') ??
              'Unable to load the dashboard.',
        );
      }
      final snapshot = AdminDashboardSnapshot.fromJson(map);
      await _cacheSnapshot(map);
      return snapshot;
    } catch (e) {
      debugPrint('AdminDashboardService.loadSnapshot error: $e');
      if (_isMissingRpc(e)) {
        final snapshot = await _loadFallback(window);
        await _cacheSnapshot(_snapshotCachePayload(snapshot));
        return snapshot;
      }
      rethrow;
    }
  }

  AdminDashboardSnapshot? readCachedSnapshot() {
    final json = _prefs?.adminDashboardCacheJson;
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      final map = supabaseRpcMap(decoded);
      if (map == null) return null;
      return AdminDashboardSnapshot.fromJson(map);
    } catch (e) {
      debugPrint('AdminDashboardService cache parse error: $e');
      return null;
    }
  }

  Future<List<AdminDashboardVerification>> listVerifications({
    required AdminDashboardVerificationFilter filter,
  }) async {
    final status = switch (filter) {
      AdminDashboardVerificationFilter.pending => 'pending',
      AdminDashboardVerificationFilter.approved => 'approved',
      AdminDashboardVerificationFilter.rejected => 'rejected',
    };
    final rows = await _supabase.client
        .from('user_verifications')
        .select(
          'verification_id, shop_name, submitted_at, verification_status, user_id',
        )
        .eq('verification_status', status)
        .order('submitted_at', ascending: false)
        .limit(8);
    final applications = <Map<String, dynamic>>[
      for (final row in rows as List)
        if (row is Map<String, dynamic>)
          row
        else if (row is Map)
          Map<String, dynamic>.from(row),
    ];
    final names = await _namesFor(
      applications
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .toSet(),
    );
    return [
      for (final row in applications)
        AdminDashboardVerification.fromJson({
          'id': row['verification_id'],
          'applicant_name': names[row['user_id'] as String?] ?? 'Applicant',
          'shop_name': row['shop_name'],
          'submitted_at': row['submitted_at'],
          'status': row['verification_status'],
        }),
    ];
  }

  Future<void> _cacheSnapshot(Map<String, dynamic> json) async {
    try {
      await _prefs?.setAdminDashboardCacheJson(jsonEncode(json));
    } catch (e) {
      debugPrint('AdminDashboardService cache write error: $e');
    }
  }

  Future<AdminDashboardSnapshot> _loadFallback(AdminDateWindow window) async {
    final fromIso = window.from.toUtc().toIso8601String();
    final toIso = window.toExclusive.toUtc().toIso8601String();
    final activeNowSince = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 15))
        .toIso8601String();

    final usersInPeriod = await _supabase.client
        .from('users')
        .select('created_at, last_active_at')
        .gte('created_at', fromIso)
        .lt('created_at', toIso);
    final activeInPeriod = await _supabase.client
        .from('users')
        .select('user_id')
        .eq('account_status', 'active')
        .gte('last_active_at', fromIso)
        .lt('last_active_at', toIso);
    final pending = await _count(
      'user_verifications',
      column: 'verification_status',
      equals: 'pending',
    );
    final verificationsInPeriod = await _supabase.client
        .from('user_verifications')
        .select('submitted_at')
        .gte('submitted_at', fromIso)
        .lt('submitted_at', toIso);
    final openReports = await _count(
      'reports',
      column: 'status',
      equals: kAdminReportOpenStatus,
    );
    final reportsInPeriod = await _supabase.client
        .from('reports')
        .select('created_at, status')
        .gte('created_at', fromIso)
        .lt('created_at', toIso);
    final ordersInPeriod = await _supabase.client
        .from('orders')
        .select('created_at, order_status')
        .gte('created_at', fromIso)
        .lt('created_at', toIso);
    final disputes = await _count(
      'delivery_disputes',
      column: 'status',
      equals: kAdminDisputeOpenStatus,
    );

    final days = _daysBetween(window.from, window.toExclusive);
    final lists = await (
      listVerifications(filter: AdminDashboardVerificationFilter.pending),
      _recentReportsFallback(fromIso: fromIso, toIso: toIso),
    ).wait;

    return AdminDashboardSnapshot(
      generatedAt: DateTime.now().toUtc(),
      bucket: days.length > 62 ? 'month' : 'day',
      counts: AdminDashboardCounts(
        registeredInPeriod: (usersInPeriod as List).length,
        activeInPeriod: (activeInPeriod as List).length,
        activeNow: await _countActiveUsers(activeNowSince),
        pendingVerifications: pending,
        verificationsSubmitted: (verificationsInPeriod as List).length,
        openReports: openReports,
        reportsSubmitted: (reportsInPeriod as List).length,
        ordersPlaced: (ordersInPeriod as List).length,
        openDisputes: disputes,
      ),
      registrations: _pointsFromRows(usersInPeriod, days, 'created_at'),
      ordersByDay: _pointsFromRows(ordersInPeriod, days, 'created_at'),
      ordersByStatus: _statusCounts(ordersInPeriod, 'order_status'),
      reportsByDay: _pointsFromRows(reportsInPeriod, days, 'created_at'),
      reportsByStatus: _statusCounts(reportsInPeriod, 'status'),
      pendingVerifications: lists.$1,
      recentReports: lists.$2,
      recentOrders: const [],
    );
  }

  Future<List<AdminDashboardReport>> _recentReportsFallback({
    String? fromIso,
    String? toIso,
  }) async {
    var query = _supabase.client
        .from('reports')
        .select(
          'report_id, reporter_id, reported_user_id, category, order_id, created_at, status',
        );
    if (fromIso != null) query = query.gte('created_at', fromIso);
    if (toIso != null) query = query.lt('created_at', toIso);
    final rows = await query.order('created_at', ascending: false).limit(5);
    final reports = <Map<String, dynamic>>[
      for (final row in rows as List)
        if (row is Map<String, dynamic>)
          row
        else if (row is Map)
          Map<String, dynamic>.from(row),
    ];
    final userIds = <String>{
      for (final row in reports) ...[
        if (row['reporter_id'] is String) row['reporter_id'] as String,
        if (row['reported_user_id'] is String)
          row['reported_user_id'] as String,
      ],
    };
    final names = await _namesFor(userIds);
    final roles = await _rolesFor(userIds);
    final orderNumbers = await _orderNumbersFor({
      for (final row in reports)
        if (row['order_id'] is String) row['order_id'] as String,
    });
    return [
      for (final row in reports)
        AdminDashboardReport.fromJson({
          'id': row['report_id'],
          'reporter_name': names[row['reporter_id'] as String?] ?? 'Member',
          'reported_name':
              names[row['reported_user_id'] as String?] ?? 'Member',
          'reported_role': roles[row['reported_user_id'] as String?],
          'category': row['category'],
          'order_number': orderNumbers[row['order_id'] as String?],
          'created_at': row['created_at'],
          'status': row['status'],
        }),
    ];
  }

  Future<int> _count(String table, {String? column, String? equals}) async {
    var query = _supabase.client.from(table).select(column ?? 'created_at');
    if (column != null && equals != null) {
      query = query.eq(column, equals);
    }
    final rows = await query;
    return (rows as List).length;
  }

  Future<int> _countActiveUsers(String sinceIso) async {
    final rows = await _supabase.client
        .from('users')
        .select('user_id')
        .eq('account_status', 'active')
        .gte('last_active_at', sinceIso);
    return (rows as List).length;
  }

  Future<Map<String, String>> _namesFor(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, full_name, username')
          .inFilter('user_id', ids.toList());
      return {
        for (final row in rows as List)
          if (row is Map)
            row['user_id'] as String:
                ((row['full_name'] as String?)?.trim().isNotEmpty == true
                ? row['full_name'] as String
                : (row['username'] as String?)?.trim() ?? 'Member'),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _rolesFor(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, role')
          .inFilter('user_id', ids.toList());
      return {
        for (final row in rows as List)
          if (row is Map && row['role'] is String)
            row['user_id'] as String: row['role'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _orderNumbersFor(Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase.client
          .from('orders')
          .select('order_id, order_number')
          .inFilter('order_id', ids.toList());
      return {
        for (final row in rows as List)
          if (row is Map && row['order_number'] is String)
            row['order_id'] as String: row['order_number'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  bool _isMissingRpc(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('admin_dashboard_snapshot') &&
        (text.contains('could not find') ||
            text.contains('pgrst202') ||
            text.contains('does not exist'));
  }

  Map<String, dynamic> _snapshotCachePayload(AdminDashboardSnapshot snapshot) {
    return {
      'success': true,
      'generated_at': snapshot.generatedAt.toIso8601String(),
      'bucket': snapshot.bucket,
      'counts': {
        'period_users': snapshot.counts.registeredInPeriod,
        'period_active': snapshot.counts.activeInPeriod,
        'active_now': snapshot.counts.activeNow,
        'pending_verifications': snapshot.counts.pendingVerifications,
        'period_verifications': snapshot.counts.verificationsSubmitted,
        'open_reports': snapshot.counts.openReports,
        'period_reports': snapshot.counts.reportsSubmitted,
        'period_orders': snapshot.counts.ordersPlaced,
        'open_disputes': snapshot.counts.openDisputes,
      },
      'registrations': [
        for (final point in snapshot.registrations)
          {'day': point.day.toIso8601String(), 'count': point.count},
      ],
      'orders_by_day': [
        for (final point in snapshot.ordersByDay)
          {'day': point.day.toIso8601String(), 'count': point.count},
      ],
      'orders_by_status': [
        for (final item in snapshot.ordersByStatus)
          {'status': item.status, 'count': item.count},
      ],
      'reports_by_day': [
        for (final point in snapshot.reportsByDay)
          {'day': point.day.toIso8601String(), 'count': point.count},
      ],
      'reports_by_status': [
        for (final item in snapshot.reportsByStatus)
          {'status': item.status, 'count': item.count},
      ],
      'pending_verifications': [
        for (final item in snapshot.pendingVerifications)
          {
            'id': item.id,
            'applicant_name': item.applicantName,
            'shop_name': item.shopName,
            'submitted_at': item.submittedAt.toIso8601String(),
            'status': item.status,
          },
      ],
      'recent_reports': [
        for (final item in snapshot.recentReports)
          {
            'id': item.id,
            'reporter_role': item.reporterRole,
            'reported_name': item.reportedName,
            'reported_role': item.reportedRole,
            'category': item.category,
            'order_number': item.orderNumber,
            'created_at': item.createdAt.toIso8601String(),
            'status': item.status,
          },
      ],
      'recent_orders': [
        for (final item in snapshot.recentOrders)
          {
            'order_number': item.orderNumber,
            'status': item.status,
            'total_amount': item.totalAmount,
            'created_at': item.createdAt.toIso8601String(),
          },
      ],
    };
  }
}

List<DateTime> _daysBetween(DateTime from, DateTime toExclusive) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(
    toExclusive.year,
    toExclusive.month,
    toExclusive.day,
  ).subtract(const Duration(days: 1));
  if (end.isBefore(start)) return [start];
  final days = end.difference(start).inDays + 1;
  return [for (var i = 0; i < days; i++) start.add(Duration(days: i))];
}

List<AdminDashboardPoint> _pointsFromRows(
  Object? rows,
  List<DateTime> days,
  String column,
) {
  final counts = <String, int>{};
  if (rows is List) {
    for (final row in rows) {
      if (row is! Map) continue;
      final parsed = DateTime.tryParse('${row[column]}')?.toUtc();
      if (parsed == null) continue;
      final key =
          '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return [
    for (final day in days)
      AdminDashboardPoint(
        day: day,
        count:
            counts['${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'] ??
            0,
      ),
  ];
}

List<AdminDashboardStatusCount> _statusCounts(Object? rows, String column) {
  final counts = <String, int>{};
  if (rows is List) {
    for (final row in rows) {
      if (row is! Map) continue;
      final status = (row[column] as String?)?.trim();
      if (status == null || status.isEmpty) continue;
      counts[status] = (counts[status] ?? 0) + 1;
    }
  }
  final items = [
    for (final entry in counts.entries)
      AdminDashboardStatusCount(status: entry.key, count: entry.value),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return items;
}
