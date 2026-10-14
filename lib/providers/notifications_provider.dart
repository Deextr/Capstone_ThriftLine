import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../features/auth/domain/account_mode.dart';
import '../features/notifications/domain/notification_audience.dart';
import '../features/notifications/domain/notification_catalog.dart';
import '../models/notification_model.dart';

class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._supabase);
  final SupabaseService _supabase;
  final List<NotificationModel> _items = [];
  RealtimeChannel? _channel;
  String? _userId;
  bool _isLoading = false;
  String? _loadError;
  AccountMode _activeAccount = AccountMode.buyer;
  bool _hasSellerAccess = false;

  List<NotificationModel> get items => List.unmodifiable(
    notificationsForAccountMode(
      _items,
      _activeAccount,
      hasSellerAccess: _hasSellerAccess,
    ),
  );

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  NotificationModel? findById(String id) {
    for (final n in _items) {
      if (n.id == id) return n;
    }
    return null;
  }

  int get unreadCount => unreadNotificationsForAccountMode(
    _items,
    _activeAccount,
    hasSellerAccess: _hasSellerAccess,
  );

  void setAccountContext({
    required AccountMode mode,
    required bool hasSellerAccess,
  }) {
    final changed =
        _activeAccount != mode || _hasSellerAccess != hasSellerAccess;
    _activeAccount = mode;
    _hasSellerAccess = hasSellerAccess;
    if (changed) notifyListeners();
  }

  List<NotificationModel> forTab(String tab) =>
      items.where((n) => notificationMatchesTab(n, tab)).toList();

  Future<void> startForUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      await stop();
      return;
    }
    if (_userId == userId && _channel != null) return;
    await stop();
    _userId = userId;
    await refresh();
    _subscribe(userId);
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final rows = await _supabase.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
      _items
        ..clear()
        ..addAll(
          (rows as List).map(
            (row) => NotificationModel.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          ),
        );
    } catch (e) {
      _loadError = 'Check your connection and try again.';
      debugPrint('NotificationsProvider.refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || _items[index].isRead) return;
    _items[index] = _items[index].copyWith(isRead: true);
    notifyListeners();
    try {
      await _supabase.client
          .from('notifications')
          .update({'is_read': true})
          .eq('notification_id', id);
    } catch (e) {
      debugPrint('NotificationsProvider.markRead error: $e');
    }
  }

  Future<void> markAllRead() async {
    final userId = _userId;
    if (userId == null) return;
    final audiences = notificationAudienceDbValuesForMode(
      _activeAccount,
      hasSellerAccess: _hasSellerAccess,
    );
    final visibleIds = items.where((n) => !n.isRead).map((n) => n.id).toSet();
    if (visibleIds.isEmpty) return;

    for (var i = 0; i < _items.length; i++) {
      if (visibleIds.contains(_items[i].id)) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
    try {
      await _supabase.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false)
          .inFilter('audience', audiences);
    } catch (e) {
      debugPrint('NotificationsProvider.markAllRead error: $e');
    }
  }

  void _subscribe(String userId) {
    _channel = _supabase.client.channel('notifications-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final item = NotificationModel.fromJson(payload.newRecord);
          if (_items.any((n) => n.id == item.id)) return;
          _items.insert(0, item);
          notifyListeners();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final item = NotificationModel.fromJson(payload.newRecord);
          final index = _items.indexWhere((n) => n.id == item.id);
          if (index < 0) return;
          _items[index] = item;
          notifyListeners();
        },
      )
      ..subscribe();
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _userId = null;
    _loadError = null;
    _items.clear();
    if (channel != null) await _supabase.client.removeChannel(channel);
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
