import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/chat_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/conversation_service.dart';

class ChatListController extends ChangeNotifier {
  ChatListController({
    required SupabaseService supabase,
    required AuthProvider auth,
    ConversationService? conversations,
  }) : _auth = auth,
       _conversations = conversations ?? ConversationService(supabase) {
    load();
  }

  final AuthProvider _auth;
  final ConversationService _conversations;

  List<ChatModel> _chats = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<ChatModel> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _chats = [];
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _chats = await _conversations.loadConversations(myId);
    } catch (e) {
      debugPrint('ChatListController.load error: $e');
      _errorMessage = 'Unable to load messages.';
      _chats = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
