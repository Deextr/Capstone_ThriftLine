import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/chat_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/conversation_service.dart';

class ChatListController extends ChangeNotifier {
  ChatListController({
    required SupabaseService supabase,
    required AuthProvider auth,
    ConversationService? conversations,
  }) : _supabase = supabase,
       _auth = auth,
       _conversations = conversations ?? ConversationService(supabase) {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ConversationService _conversations;

  List<ChatModel> _chats = [];
  bool _isLoading = true;
  String? _errorMessage;
  RealtimeChannel? _channel;
  Timer? _reloadDebounce;
  bool _disposed = false;
  bool _subscribed = false;
  bool _initialSubscribe = true;

  List<ChatModel> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool quiet = false}) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _chats = [];
      _isLoading = false;
      notifyListeners();
      return;
    }
    if (!quiet) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _chats = await _conversations.loadConversations(myId);
      _errorMessage = null;
    } catch (e) {
      debugPrint('ChatListController.load error: $e');
      _errorMessage = 'Unable to load messages.';
      if (!quiet) _chats = [];
    } finally {
      _isLoading = false;
      _subscribe(myId);
      if (!_disposed) notifyListeners();
    }
  }

  void _subscribe(String userId) {
    if (_subscribed || _disposed) return;
    _subscribed = true;
    try {
      _channel = _supabase.client
          .channel('conversations-inbox-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversations',
            callback: (_) => _scheduleQuietReload(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (_) => _scheduleQuietReload(),
          )
          .subscribe((status, [_]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (_initialSubscribe) {
                _initialSubscribe = false;
                return;
              }
              _scheduleQuietReload();
            }
          });
    } catch (e) {
      debugPrint('ChatListController realtime error: $e');
      _subscribed = false;
    }
  }

  void _scheduleQuietReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      unawaited(load(quiet: true));
    });
  }

  Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    _subscribed = false;
    if (channel != null) {
      try {
        await _supabase.client.removeChannel(channel);
      } catch (e) {
        debugPrint('ChatListController unsubscribe error: $e');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reloadDebounce?.cancel();
    unawaited(_unsubscribe());
    super.dispose();
  }
}
