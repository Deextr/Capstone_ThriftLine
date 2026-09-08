import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/chat_model.dart';
import '../../../models/enums.dart';
import '../../../models/message_model.dart';
import '../../../providers/auth_provider.dart';
import '../data/conversation_service.dart';

class ChatDetailController extends ChangeNotifier {
  ChatDetailController({
    required this.conversationId,
    required SupabaseService supabase,
    required AuthProvider auth,
    ConversationService? conversations,
  }) : _auth = auth,
       _conversations = conversations ?? ConversationService(supabase) {
    load();
  }

  final String conversationId;
  final AuthProvider _auth;
  final ConversationService _conversations;

  ChatModel? _chat;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  ChatModel? get chat => _chat;
  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get myId => _auth.user?.id;

  Future<void> load() async {
    final id = _auth.user?.id;
    if (id == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _chat = await _conversations.loadConversation(conversationId, id);
      _messages = await _conversations.loadMessages(conversationId);
    } catch (e) {
      debugPrint('ChatDetailController.load error: $e');
      _errorMessage = 'Unable to load this conversation.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> sendText(String content) async {
    final id = _auth.user?.id;
    final trimmed = content.trim();
    if (id == null) return 'Please sign in to send a message.';
    if (trimmed.isEmpty) return 'Write a message first.';
    _isSending = true;
    notifyListeners();
    try {
      await _conversations.sendMessage(
        conversationId: conversationId,
        senderId: id,
        content: trimmed,
      );
      await load();
      return null;
    } catch (e) {
      debugPrint('ChatDetailController.sendText error: $e');
      return 'Could not send that message.';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<String?> sendOffer({required double amount, String? note}) async {
    final id = _auth.user?.id;
    if (id == null) return 'Please sign in to send an offer.';
    _isSending = true;
    notifyListeners();
    try {
      await _conversations.sendMessage(
        conversationId: conversationId,
        senderId: id,
        content: (note == null || note.trim().isEmpty)
            ? 'Sent an offer'
            : note.trim(),
        type: MessageType.offer,
        offerAmount: amount,
      );
      await load();
      return null;
    } catch (e) {
      debugPrint('ChatDetailController.sendOffer error: $e');
      return 'Could not send that offer.';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
