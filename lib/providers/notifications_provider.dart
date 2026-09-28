import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../models/enums.dart';
import '../models/notification_model.dart';

class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._supabase);
  final SupabaseService _supabase;
  final List<NotificationModel> _items = [];
  RealtimeChannel? _channel;
  String? _userId;
  bool _isLoading = false;

  List<NotificationModel> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  int get unreadCount => _items.where((n) => !n.isRead).length;

  List<NotificationModel> forTab(String tab) {
    return switch (tab) {
      'orders' => _items
          .where((n) =>
              n.type == NotificationType.shipped ||
              n.type == NotificationType.orderConfirmed)
          .toList(),
      'bids' => _items
          .where((n) =>
              n.type == NotificationType.outbid ||
              n.type == NotificationType.wonBid)
          .toList(),
      'messages' =>
        _items.where((n) => n.type == NotificationType.message).toList(),
      'system' => _items
          .where((n) =>
              n.type == NotificationType.system ||
              n.type == NotificationType.verificationSubmitted ||
              n.type == NotificationType.verificationApproved ||
              n.type == NotificationType.verificationRejected)
          .toList(),
      _ => _items,
    };
  }

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
        ..addAll((rows as List).map((row) =>
            NotificationModel.fromJson(Map<String, dynamic>.from(row as Map))));
    } catch (e) {
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
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isRead) _items[i] = _items[i].copyWith(isRead: true);
    }
    notifyListeners();
    try {
      await _supabase.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
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
      ..subscribe();
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _userId = null;
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
