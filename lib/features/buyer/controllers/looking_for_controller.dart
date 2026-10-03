import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/enums.dart';
import '../../../models/looking_for_model.dart';
import '../../../providers/auth_provider.dart';
import '../domain/looking_for_lifecycle.dart';
import '../../chat/data/chat_action_result.dart';
import '../../chat/data/conversation_service.dart';

/// True only after a fetch finishes with zero rows — never during the first load.
bool lookingForShowsEmpty({required bool isLoading, required int postCount}) =>
    !isLoading && postCount == 0;

const _lookingForBucket = 'looking-for';

/// Object key inside the `looking-for` bucket, or null if [url] is not ours.
@visibleForTesting
String? lookingForStoragePathFromPublicUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  const marker = '/object/public/$_lookingForBucket/';
  final start = url.indexOf(marker);
  if (start < 0) return null;
  final raw = url.substring(start + marker.length).split('?').first;
  if (raw.isEmpty) return null;
  return Uri.decodeComponent(raw);
}

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
  DateTime _serverNow = DateTime.now().toUtc();
  DateTime? _restrictedUntil;

  List<LookingForModel> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isPosting => _isPosting;
  String? get errorMessage => _errorMessage;
  AuthProvider get auth => _auth;
  ConversationService get conversations => _conversations;
  DateTime get serverNow => _serverNow;

  bool get isPostingRestricted =>
      _restrictedUntil != null && _restrictedUntil!.isAfter(_serverNow);

  String? get postingRestrictionMessage => isPostingRestricted
      ? lookingForRestrictionMessage(_restrictedUntil!)
      : null;

  List<LookingForModel> get browsePosts =>
      _posts.where((post) => post.showInBrowse).toList();

  List<LookingForModel> get myPosts {
    final id = _auth.user?.id;
    if (id == null) return const [];
    return _posts.where((post) => post.buyerId == id).toList();
  }

  List<LookingForModel> get myActivePosts =>
      myPosts.where((post) => post.showInMyActive).toList();

  List<LookingForModel> get myInactivePosts =>
      myPosts.where((post) => post.showInInactive).toList();

  Future<void> loadPosts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _syncClock();
      await _loadRestriction();
      try {
        await _supabase.client.rpc('notify_my_expired_looking_for_requests');
      } catch (e) {
        debugPrint('LookingForController expiry notice error: $e');
      }

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
        ).copyWith(observedAt: _serverNow);
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
      final postId = const Uuid().v4();
      String? imageUrl;
      if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
        try {
          imageUrl = await _uploadReferenceImage(
            userId: user.id,
            postId: postId,
            bytes: referenceImageBytes,
          );
        } catch (e) {
          debugPrint('LookingForController image upload error: $e');
          return 'Could not upload the reference image. Try again without it, or check storage.';
        }
      }

      final error = await _callLookingFor(
        'create_looking_for_request',
        {
          'p_title': title.trim(),
          'p_description': description.trim(),
          'p_category_name': category.label,
          'p_budget_min': budgetMin,
          'p_budget_max': budgetMax,
          'p_size': (size == null || size.trim().isEmpty) ? null : size.trim(),
          'p_image_url': imageUrl,
        },
        'Could not post your request. Please try again.',
      );
      if (error != null) {
        await _deleteReferenceImage(imageUrl);
        return error;
      }
      return null;
    } catch (e) {
      debugPrint('LookingForController.createPost error: $e');
      return 'Could not post your request. Please try again.';
    } finally {
      _isPosting = false;
    }
  }

  Future<String?> repostPost({
    required String sourcePostId,
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
    if (user == null) return 'Please sign in to repost this request.';
    if (title.trim().isEmpty) return 'Please enter what you are looking for.';

    _isPosting = true;
    try {
      String? imageUrl;
      if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
        try {
          imageUrl = await _uploadReferenceImage(
            userId: user.id,
            postId: const Uuid().v4(),
            bytes: referenceImageBytes,
          );
        } catch (e) {
          debugPrint('LookingForController repost image error: $e');
          return 'Could not upload the reference image.';
        }
      }

      final error = await _callLookingFor(
        'repost_looking_for_request',
        {
          'p_post_id': sourcePostId,
          'p_title': title.trim(),
          'p_description': description.trim(),
          'p_category_name': category.label,
          'p_budget_min': budgetMin,
          'p_budget_max': budgetMax,
          'p_size': (size == null || size.trim().isEmpty) ? null : size.trim(),
          'p_image_url': imageUrl,
          'p_clear_image': clearReferenceImage && imageUrl == null,
        },
        'Could not repost this request. Please try again.',
      );
      if (error != null) {
        await _deleteReferenceImage(imageUrl);
        return error;
      }
      return null;
    } catch (e) {
      debugPrint('LookingForController.repostPost error: $e');
      return 'Could not repost this request. Please try again.';
    } finally {
      _isPosting = false;
    }
  }

  Future<String?> reportPost({
    required String postId,
    required String reason,
    String? details,
  }) async {
    final detailsError = lookingForReportDetailsError(
      reason: reason,
      details: details ?? '',
    );
    if (detailsError != null) return detailsError;
    return _callLookingFor(
      'report_looking_for_request',
      {
        'p_post_id': postId,
        'p_reason': reason,
        'p_details': (details == null || details.trim().isEmpty)
            ? null
            : details.trim(),
      },
      'Could not send this report. Please try again.',
    );
  }

  Future<LookingForModel?> loadPostById(String postId) async {
    try {
      await _syncClock();
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
      return LookingForModel.fromSupabase(
        row,
        buyer: buyer,
      ).copyWith(observedAt: _serverNow);
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
      final current = await _supabase.client
          .from('looking_for_posts')
          .select('reference_image_url')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      final previousUrl = current?['reference_image_url'] as String?;

      String? imageUrl;
      final replacing =
          referenceImageBytes != null && referenceImageBytes.isNotEmpty;
      if (replacing) {
        try {
          imageUrl = await _uploadReferenceImage(
            userId: user.id,
            postId: postId,
            bytes: referenceImageBytes,
          );
        } catch (e) {
          debugPrint('LookingForController image update error: $e');
          return 'Could not upload the reference image.';
        }
      }

      final error = await _callLookingFor(
        'update_looking_for_request',
        {
          'p_post_id': postId,
          'p_title': title.trim(),
          'p_description': description.trim(),
          'p_category_name': category.label,
          'p_budget_min': budgetMin,
          'p_budget_max': budgetMax,
          'p_size': (size == null || size.trim().isEmpty) ? null : size.trim(),
          'p_image_url': replacing ? imageUrl : null,
          'p_clear_image': clearReferenceImage && !replacing,
        },
        'Could not save your request. Please try again.',
      );
      if (error != null) {
        if (replacing) await _deleteReferenceImage(imageUrl);
        return error;
      }
      if (replacing || clearReferenceImage) {
        await _deleteReferenceImage(previousUrl);
      }

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
      final row = await _supabase.client
          .from('looking_for_posts')
          .select('reference_image_url')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      final error = await _callLookingFor(
        'delete_looking_for_request',
        {'p_post_id': postId},
        'Could not delete this request. Please try again.',
      );
      if (error != null) return error;
      await _deleteReferenceImage(row?['reference_image_url'] as String?);
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
    if (!post.showInBrowse) {
      return const ChatActionResult.error('This request is no longer active.');
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

  Future<void> _syncClock() async {
    try {
      final raw = await _supabase.client.rpc('looking_for_server_now');
      final stamp = DateTime.tryParse(
        supabaseRpcMap(raw)?['now']?.toString() ?? '',
      );
      if (stamp != null) _serverNow = stamp.toUtc();
    } catch (e) {
      debugPrint('LookingForController clock error: $e');
    }
  }

  Future<void> _loadRestriction() async {
    final id = _auth.user?.id;
    _restrictedUntil = null;
    if (id == null) return;
    try {
      final row = await _supabase.client
          .from('looking_for_account_sanctions')
          .select('restricted_until, permanently_disabled_at')
          .eq('user_id', id)
          .maybeSingle();
      final until = row?['restricted_until'];
      final disabled = row?['permanently_disabled_at'];
      if (disabled != null) {
        _restrictedUntil = DateTime.utc(9999);
        return;
      }
      if (until is String) {
        _restrictedUntil = DateTime.tryParse(until)?.toUtc();
      }
    } catch (e) {
      debugPrint('LookingForController restriction error: $e');
    }
  }

  Future<String?> _callLookingFor(
    String fn,
    Map<String, dynamic> params,
    String fallback,
  ) async {
    try {
      final raw = await _supabase.client.rpc(fn, params: params);
      if (supabaseRpcSuccess(raw)) return null;
      return supabaseRpcError(raw, fallback: fallback);
    } catch (e) {
      debugPrint('LookingForController.$fn error: $e');
      return fallback;
    }
  }

  Future<String> _uploadReferenceImage({
    required String userId,
    required String postId,
    required Uint8List bytes,
  }) async {
    final path = '$userId/$postId/${const Uuid().v4()}.jpg';
    await _supabase.client.storage
        .from(_lookingForBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return _supabase.client.storage.from(_lookingForBucket).getPublicUrl(path);
  }

  Future<void> _deleteReferenceImage(String? publicUrl) async {
    final path = lookingForStoragePathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await _supabase.client.storage.from(_lookingForBucket).remove([path]);
    } catch (e) {
      debugPrint('LookingForController image delete error: $e');
    }
  }
}
