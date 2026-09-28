import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    ImagePicker? imagePicker,
  }) : _supabase = supabase,
       _auth = auth,
       _conversations = conversations ?? ConversationService(supabase),
       _imagePicker = imagePicker ?? ImagePicker() {
    load();
  }

  final String conversationId;
  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ConversationService _conversations;
  final ImagePicker _imagePicker;

  ChatModel? _chat;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  RealtimeChannel? _channel;
  bool _disposed = false;
  bool _subscribed = false;
  bool _initialSubscribe = true;
  final Map<String, String> _signedUrls = {};

  ChatModel? get chat => _chat;
  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get myId => _auth.user?.id;

  Future<void> load({bool quiet = false}) async {
    final id = _auth.user?.id;
    if (id == null) return;
    if (!quiet) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _chat = await _conversations.loadConversation(conversationId, id);
      _messages = await _conversations.loadMessages(conversationId);
      try {
        await _conversations.markRead(conversationId);
        _chat =
            await _conversations.loadConversation(conversationId, id) ?? _chat;
      } catch (e) {
        debugPrint('ChatDetailController.markRead error: $e');
      }
    } catch (e) {
      debugPrint('ChatDetailController.load error: $e');
      _errorMessage = 'Unable to load this conversation.';
    } finally {
      _subscribe();
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _subscribe() {
    if (_subscribed || _disposed) return;
    _subscribed = true;
    try {
      _channel = _supabase.client
          .channel('messages-thread-$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: _onMessageInsert,
          )
          .subscribe((status, [_]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (_initialSubscribe) {
                _initialSubscribe = false;
                return;
              }
              unawaited(load(quiet: true));
            }
          });
    } catch (e) {
      debugPrint('ChatDetailController realtime error: $e');
      _subscribed = false;
    }
  }

  void _onMessageInsert(PostgresChangePayload payload) {
    if (_disposed) return;
    final row = payload.newRecord;
    final incoming = MessageModel.fromSupabase(row);
    if (incoming.id.isEmpty) return;
    _messages = upsertMessages(_messages, incoming);
    notifyListeners();
    final id = _auth.user?.id;
    if (id != null && incoming.senderId != id) {
      unawaited(_markReadQuiet());
    }
  }

  Future<void> _markReadQuiet() async {
    try {
      await _conversations.markRead(conversationId);
    } catch (e) {
      debugPrint('ChatDetailController.markRead error: $e');
    }
  }

  Future<String?> signedUrlFor(MessageModel message) async {
    final path = message.attachmentPath;
    if (path == null || path.isEmpty) return null;
    final cached = _signedUrls[path];
    if (cached != null) return cached;
    final url = await _conversations.signedAttachmentUrl(path);
    if (url != null) _signedUrls[path] = url;
    return url;
  }

  Future<String?> sendText(String content) async {
    final id = _auth.user?.id;
    final trimmed = content.trim();
    if (id == null) return 'Please sign in to send a message.';
    if (trimmed.isEmpty) return 'Write a message first.';
    _isSending = true;
    notifyListeners();
    try {
      final sent = await _conversations.sendMessage(
        conversationId: conversationId,
        senderId: id,
        content: trimmed,
      );
      _messages = upsertMessages(_messages, sent);
      return null;
    } catch (e) {
      debugPrint('ChatDetailController.sendText error: $e');
      return 'Could not send that message.';
    } finally {
      _isSending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> sendOffer({required double amount, String? note}) async {
    final id = _auth.user?.id;
    if (id == null) return 'Please sign in to send an offer.';
    _isSending = true;
    notifyListeners();
    try {
      final sent = await _conversations.sendMessage(
        conversationId: conversationId,
        senderId: id,
        content: (note == null || note.trim().isEmpty)
            ? 'Sent an offer'
            : note.trim(),
        type: MessageType.offer,
        offerAmount: amount,
      );
      _messages = upsertMessages(_messages, sent);
      return null;
    } catch (e) {
      debugPrint('ChatDetailController.sendOffer error: $e');
      return 'Could not send that offer.';
    } finally {
      _isSending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> pickAndSendImage() async {
    final id = _auth.user?.id;
    if (id == null) return 'Please sign in to send a photo.';
    final xfile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (xfile == null) return null;

    _isSending = true;
    notifyListeners();
    String? uploadedPath;
    try {
      final bytes = await xfile.readAsBytes();
      final contentType = xfile.mimeType ?? _mimeFromName(xfile.name);
      uploadedPath = await _conversations.uploadImageAttachment(
        conversationId: conversationId,
        userId: id,
        bytes: bytes,
        filename: xfile.name,
        contentType: contentType,
      );
      final sent = await _conversations.sendMessage(
        conversationId: conversationId,
        senderId: id,
        content: '',
        type: MessageType.image,
        attachmentPath: uploadedPath,
      );
      _messages = upsertMessages(_messages, sent);
      return null;
    } catch (e) {
      debugPrint('ChatDetailController.pickAndSendImage error: $e');
      if (uploadedPath != null) {
        await _conversations.deleteAttachment(uploadedPath);
      }
      if (e is StateError) return e.message;
      return 'Could not send that photo.';
    } finally {
      _isSending = false;
      if (!_disposed) notifyListeners();
    }
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    _subscribed = false;
    if (channel != null) {
      try {
        await _supabase.client.removeChannel(channel);
      } catch (e) {
        debugPrint('ChatDetailController unsubscribe error: $e');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_unsubscribe());
    super.dispose();
  }
}
