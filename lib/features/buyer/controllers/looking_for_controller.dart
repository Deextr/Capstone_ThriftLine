import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/looking_for_model.dart';
import '../../../providers/auth_provider.dart';
import '../../chat/data/chat_action_result.dart';
import '../../chat/data/conversation_service.dart';

/// True only after a fetch finishes with zero rows — never during the first load.
bool lookingForShowsEmpty({required bool isLoading, required int postCount}) =>
    !isLoading && postCount == 0;

class LookingForController extends ChangeNotifier {
  LookingForController({
    required SupabaseService supabase,
    required AuthProvider auth,
    ConversationService? conversations,
    bool loadOnStart = true,
  }) : _supabase = supabase,
       _auth = auth,
       _conversations = conversations ?? ConversationService(supabase) {
    if (loadOnStart) loadPosts();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ConversationService _conversations;

  List<LookingForModel> _posts = [];
  bool _isLoading = true;
  bool _isPosting = false;
  String? _errorMessage;

  List<LookingForModel> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isPosting => _isPosting;
  String? get errorMessage => _errorMessage;
  AuthProvider get auth => _auth;
  ConversationService get conversations => _conversations;

  List<LookingForModel> get myPosts {
    final id = _auth.user?.id;
    if (id == null) return const [];
    return _posts.where((p) => p.buyerId == id).toList();
  }

  Future<void> loadPosts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.client
          .from('looking_for_posts')
          .select('''
            *,
            category:categories (category_name)
          ''')
          .order('created_at', ascending: false)
          .limit(50);

      final rows = response as List<dynamic>;
      final buyerIds = rows
          .map((r) => (r as Map<String, dynamic>)['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final buyers = <String, Map<String, dynamic>>{};
      if (buyerIds.isNotEmpty) {
        try {
          final profiles = await _supabase.client
              .from('user_public_profiles')
              .select()
              .inFilter('user_id', buyerIds);
          for (final p in profiles as List<dynamic>) {
            final map = p as Map<String, dynamic>;
            final id = map['user_id'] as String?;
            if (id != null) buyers[id] = map;
          }
        } catch (e) {
          debugPrint('LookingForController: profiles error ($e)');
        }
      }

      _posts = rows.map((r) {
        final map = r as Map<String, dynamic>;
        final uid = map['user_id'] as String?;
        return LookingForModel.fromSupabase(
          map,
          buyer: uid != null ? buyers[uid] : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('LookingForController.loadPosts error: $e');
      _errorMessage = 'Unable to load requests.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> createPost({
    required String title,
    required String description,
    required ProductCategory category,
    required double budgetMin,
    required double budgetMax,
    String? size,
    Uint8List? referenceImageBytes,
  }) async {
    final user = _auth.user;
    if (user == null) return 'Please sign in to post a request.';
    if (title.trim().isEmpty) return 'Please enter what you are looking for.';

    // Do not notifyListeners here. The create sheet owns its submitting
    // spinner; notifying would rebuild Looking For (TabBar / NestedScrollView)
    // under the open modal and trip '_dependents.isEmpty'.
    _isPosting = true;

    try {
      String? categoryId;
      try {
        final cat = await _supabase.client
            .from('categories')
            .select('category_id')
            .ilike('category_name', category.label)
            .maybeSingle();
        categoryId = cat?['category_id'] as String?;
      } catch (_) {}

      final postId = const Uuid().v4();
      String? imageUrl;
      if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
        try {
          final path = '${user.id}/$postId.jpg';
          await _supabase.client.storage
              .from('looking-for')
              .uploadBinary(
                path,
                referenceImageBytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          imageUrl = _supabase.client.storage
              .from('looking-for')
              .getPublicUrl(path);
        } catch (e) {
          debugPrint('LookingForController image upload error: $e');
          return 'Could not upload the reference image. Try again without it, or check storage.';
        }
      }

      await _supabase.client.from('looking_for_posts').insert({
        'post_id': postId,
        'user_id': user.id,
        'title': title.trim(),
        'description': description.trim(),
        'preferred_size': (size == null || size.trim().isEmpty)
            ? null
            : size.trim(),
        'minimum_price': budgetMin,
        'maximum_price': budgetMax,
        'category_id': ?categoryId,
        'status': 'open',
        'reference_image_url': ?imageUrl,
      });

      return null;
    } catch (e) {
      debugPrint('LookingForController.createPost error: $e');
      return 'Could not post your request. Please try again.';
    } finally {
      _isPosting = false;
    }
  }

  Future<LookingForModel?> loadPostById(String postId) async {
    try {
      final row = await _supabase.client
          .from('looking_for_posts')
          .select('''
            *,
            category:categories (category_name)
          ''')
          .eq('post_id', postId)
          .maybeSingle();
      if (row == null) return null;
      final uid = row['user_id'] as String?;
      Map<String, dynamic>? buyer;
      if (uid != null) {
        try {
          buyer = await _supabase.client
              .from('user_public_profiles')
              .select()
              .eq('user_id', uid)
              .maybeSingle();
        } catch (_) {}
      }
      return LookingForModel.fromSupabase(row, buyer: buyer);
    } catch (e) {
      debugPrint('LookingForController.loadPostById error: $e');
      return null;
    }
  }

  Future<String?> updatePost({
    required String postId,
    required String title,
    required String description,
    required ProductCategory category,
    required double budgetMin,
    required double budgetMax,
    String? size,
    Uint8List? referenceImageBytes,
    bool clearReferenceImage = false,
  }) async {
    final user = _auth.user;
    if (user == null) return 'Please sign in to edit this request.';
    if (title.trim().isEmpty) return 'Please enter what you are looking for.';

    _isPosting = true;
    try {
      String? categoryId;
      try {
        final cat = await _supabase.client
            .from('categories')
            .select('category_id')
            .ilike('category_name', category.label)
            .maybeSingle();
        categoryId = cat?['category_id'] as String?;
      } catch (_) {}

      String? imageUrl;
      if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
        try {
          final path = '${user.id}/$postId.jpg';
          await _supabase.client.storage
              .from('looking-for')
              .uploadBinary(
                path,
                referenceImageBytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          imageUrl = _supabase.client.storage
              .from('looking-for')
              .getPublicUrl(path);
        } catch (e) {
          debugPrint('LookingForController image update error: $e');
          return 'Could not upload the reference image.';
        }
      }

      await _supabase.client
          .from('looking_for_posts')
          .update({
            'title': title.trim(),
            'description': description.trim(),
            'preferred_size': (size == null || size.trim().isEmpty)
                ? null
                : size.trim(),
            'minimum_price': budgetMin,
            'maximum_price': budgetMax,
            'category_id': ?categoryId,
            if (imageUrl != null || clearReferenceImage)
              'reference_image_url': imageUrl,
          })
          .eq('post_id', postId)
          .eq('user_id', user.id);

      return null;
    } catch (e) {
      debugPrint('LookingForController.updatePost error: $e');
      return 'Could not save your request. Please try again.';
    } finally {
      _isPosting = false;
    }
  }

  Future<String?> deletePost(String postId) async {
    final user = _auth.user;
    if (user == null) return 'Please sign in to delete this request.';
    try {
      await _supabase.client
          .from('looking_for_posts')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', user.id);
      _posts = _posts.where((p) => p.id != postId).toList();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('LookingForController.deletePost error: $e');
      return 'Could not delete this request. Please try again.';
    }
  }

  Future<String?> sharePost({
    required LookingForModel post,
    required List<String> sellerIds,
  }) async {
    final user = _auth.user;
    if (user == null) return 'Please sign in to share this request.';
    if (_auth.isSeller) {
      return 'Switch to your Buyer account to share requests.';
    }
    try {
      return await _conversations.shareLookingFor(
        myId: user.id,
        post: post,
        sellerIds: sellerIds,
      );
    } catch (e) {
      debugPrint('LookingForController.sharePost error: $e');
      return 'Could not share this request. Please try again.';
    }
  }

  Future<ChatActionResult> sendIHaveThis(LookingForModel post) async {
    final user = _auth.user;
    if (user == null) {
      return const ChatActionResult.error('Please sign in first.');
    }
    if (!_auth.isSeller) {
      return const ChatActionResult.error(
        'Switch to your Seller account to contact this buyer.',
      );
    }
    if (post.buyerId == user.id) {
      return const ChatActionResult.error(
        'You cannot respond to your own request.',
      );
    }
    try {
      final conversationId = await _conversations.sendIHaveThis(
        sellerId: user.id,
        post: post,
      );
      return ChatActionResult.ok(conversationId: conversationId);
    } catch (e) {
      debugPrint('LookingForController.sendIHaveThis error: $e');
      return const ChatActionResult.error(
        'Could not message this buyer. Please try again.',
      );
    }
  }

  Future<void> refresh() => loadPosts();
}
