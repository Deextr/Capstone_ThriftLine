import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/looking_for_model.dart';
import '../../../providers/auth_provider.dart';
import '../../chat/data/chat_action_result.dart';
import '../../chat/data/conversation_service.dart';
import 'looking_for_controller.dart';

class LookingForDetailController extends ChangeNotifier {
  LookingForDetailController({
    required this.postId,
    required SupabaseService supabase,
    required AuthProvider auth,
    ConversationService? conversations,
  }) : _auth = auth,
       _looking = LookingForController(
         supabase: supabase,
         auth: auth,
         conversations: conversations,
         loadOnStart: false,
       ) {
    load();
  }

  final String postId;
  final AuthProvider _auth;
  final LookingForController _looking;

  LookingForModel? _post;
  bool _isLoading = true;
  String? _errorMessage;

  LookingForModel? get post => _post;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  LookingForController get looking => _looking;
  bool get isOwner =>
      _auth.user?.id != null && _post?.buyerId == _auth.user?.id;
  bool get isSellerWorkspace => _auth.isSeller;

  @override
  void dispose() {
    _looking.dispose();
    super.dispose();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _post = await _looking.loadPostById(postId);
      if (_post == null) {
        _errorMessage = 'This Looking For request is no longer available.';
      }
    } catch (e) {
      debugPrint('LookingForDetailController.load error: $e');
      _errorMessage = 'Unable to load this request.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> delete() async {
    final error = await _looking.deletePost(postId);
    if (error == null) _post = null;
    notifyListeners();
    return error;
  }

  Future<ChatActionResult> sendIHaveThis() async {
    final post = _post;
    if (post == null) {
      return const ChatActionResult.error(
        'This request is no longer available.',
      );
    }
    return _looking.sendIHaveThis(post);
  }
}
