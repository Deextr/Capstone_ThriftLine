import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/chat_model.dart';
import '../../../models/enums.dart';
import '../../../models/looking_for_model.dart';
import '../../../models/message_model.dart';

class FollowedSeller {
  const FollowedSeller({
    required this.id,
    required this.name,
    required this.avatar,
    this.shopName,
  });

  final String id;
  final String name;
  final String avatar;
  final String? shopName;
}

const int kMessageAttachmentMaxBytes = 5 * 1024 * 1024;
const String kMessageAttachmentBucket = 'message-attachments';

/// Sorts a pair so `participant_a < participant_b` matches the DB constraint.
@visibleForTesting
({String a, String b}) orderedParticipantPair(String userId, String otherId) {
  return userId.compareTo(otherId) < 0
      ? (a: userId, b: otherId)
      : (a: otherId, b: userId);
}

@visibleForTesting
String lookingForShareBody(LookingForModel post) {
  final size = (post.size != null && post.size!.trim().isNotEmpty)
      ? ', size ${post.size!.trim()}'
      : '';
  return '${post.buyerName} is looking for:\n"${post.title}$size"';
}

@visibleForTesting
String lookingForIHaveThisBody() =>
    'I have an item that matches your Looking For request.';

@visibleForTesting
bool isMessageAttachmentPathFor({
  required String conversationId,
  required String userId,
  required String path,
}) {
  final parts = path.split('/');
  return parts.length >= 3 && parts[0] == conversationId && parts[1] == userId;
}

/// Inserts or replaces [incoming] by `message_id`, then sorts by created_at.
List<MessageModel> upsertMessages(
  List<MessageModel> current,
  MessageModel incoming,
) {
  if (incoming.id.isEmpty) return current;
  final byId = <String, MessageModel>{for (final m in current) m.id: m};
  byId[incoming.id] = incoming;
  final list = byId.values.toList()
    ..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
  return list;
}

String? _messageImageExtension(String filename, String contentType) {
  final lowerType = contentType.toLowerCase();
  if (lowerType.contains('png')) return 'png';
  if (lowerType.contains('webp')) return 'webp';
  if (lowerType.contains('jpeg') || lowerType.contains('jpg')) return 'jpg';
  final lowerName = filename.toLowerCase();
  if (lowerName.endsWith('.png')) return 'png';
  if (lowerName.endsWith('.webp')) return 'webp';
  if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) return 'jpg';
  return null;
}

bool _isUniqueViolation(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('23505') ||
      text.contains('duplicate') ||
      text.contains('unique');
}

class ConversationService {
  ConversationService(this._supabase);

  final SupabaseService _supabase;
  static const _uuid = Uuid();

  Future<List<ChatModel>> loadConversations(String myId) async {
    final rows = await _supabase.client
        .from('conversations')
        .select()
        .or('participant_a.eq.$myId,participant_b.eq.$myId')
        .order('last_message_at', ascending: false);

    final list = (rows as List<dynamic>)
        .map((r) => r as Map<String, dynamic>)
        .toList();
    final otherIds = list
        .map((r) {
          final a = r['participant_a'] as String?;
          final b = r['participant_b'] as String?;
          return a == myId ? b : a;
        })
        .whereType<String>()
        .toSet()
        .toList();
    final productIds = list
        .map((r) => r['product_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final others = await _profilesById(otherIds);
    final products = await _productsById(productIds);
    return list.map((r) {
      final a = r['participant_a'] as String?;
      final b = r['participant_b'] as String?;
      final otherId = a == myId ? b : a;
      final productId = r['product_id'] as String?;
      return ChatModel.fromSupabase(
        r,
        myId: myId,
        other: otherId != null ? others[otherId] : null,
        product: productId != null ? products[productId] : null,
      );
    }).toList();
  }

  Future<ChatModel?> loadConversation(
    String conversationId,
    String myId,
  ) async {
    final row = await _supabase.client
        .from('conversations')
        .select()
        .eq('conversation_id', conversationId)
        .maybeSingle();
    if (row == null) return null;
    final a = row['participant_a'] as String?;
    final b = row['participant_b'] as String?;
    final otherId = a == myId ? b : a;
    final productId = row['product_id'] as String?;
    final others = otherId != null
        ? await _profilesById([otherId])
        : <String, Map<String, dynamic>>{};
    final products = productId != null
        ? await _productsById([productId])
        : <String, Map<String, dynamic>>{};
    return ChatModel.fromSupabase(
      row,
      myId: myId,
      other: otherId != null ? others[otherId] : null,
      product: productId != null ? products[productId] : null,
    );
  }

  Future<List<MessageModel>> loadMessages(String conversationId) async {
    try {
      final rows = await _supabase.client
          .from('messages')
          .select('''
            *,
            looking_for_post:looking_for_posts (
              post_id,
              title,
              reference_image_url
            )
          ''')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return (rows as List<dynamic>)
          .map((r) => MessageModel.fromSupabase(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ConversationService.loadMessages embed error ($e)');
      final rows = await _supabase.client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return (rows as List<dynamic>)
          .map((r) => MessageModel.fromSupabase(r as Map<String, dynamic>))
          .toList();
    }
  }

  /// Opens the existing thread for this pair (+ optional product) or creates it.
  ///
  /// `productId == null` is the general thread used by Looking For / I Have This.
  /// A non-null product id is a separate listing-linked thread.
  Future<String> openOrCreate({
    required String myId,
    required String otherId,
    String? productId,
  }) async {
    if (myId == otherId) {
      throw StateError('Cannot open a conversation with yourself.');
    }
    final pair = orderedParticipantPair(myId, otherId);
    final existing = await _findConversation(
      participantA: pair.a,
      participantB: pair.b,
      productId: productId,
    );
    if (existing != null) return existing;

    try {
      final insert = <String, dynamic>{
        'participant_a': pair.a,
        'participant_b': pair.b,
        'product_id': ?productId,
      };
      final row = await _supabase.client
          .from('conversations')
          .insert(insert)
          .select('conversation_id')
          .single();
      return row['conversation_id'] as String;
    } catch (e) {
      if (!_isUniqueViolation(e)) rethrow;
      final retry = await _findConversation(
        participantA: pair.a,
        participantB: pair.b,
        productId: productId,
      );
      if (retry != null) return retry;
      rethrow;
    }
  }

  Future<String?> _findConversation({
    required String participantA,
    required String participantB,
    String? productId,
  }) async {
    var query = _supabase.client
        .from('conversations')
        .select('conversation_id')
        .eq('participant_a', participantA)
        .eq('participant_b', participantB);
    query = productId == null
        ? query.isFilter('product_id', null)
        : query.eq('product_id', productId);
    final row = await query.maybeSingle();
    return row?['conversation_id'] as String?;
  }

  Future<MessageModel> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    MessageType type = MessageType.text,
    String? lookingForPostId,
    double? offerAmount,
    String? attachmentPath,
  }) async {
    final sessionId = _supabase.currentUser?.id;
    if (sessionId != null && sessionId != senderId) {
      throw StateError('Cannot send as another user.');
    }
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': sessionId ?? senderId,
      'content': content,
      'message_type': type.dbValue,
      'looking_for_post_id': ?lookingForPostId,
      'offer_amount': ?offerAmount,
      'attachment_path': ?attachmentPath,
    };
    // sender_id is also overwritten by the BEFORE INSERT trigger to auth.uid().
    final row = await _supabase.client
        .from('messages')
        .insert(payload)
        .select()
        .single();
    return MessageModel.fromSupabase(row);
  }

  Future<void> markRead(String conversationId) async {
    await _supabase.client.rpc(
      'mark_conversation_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<String> uploadImageAttachment({
    required String conversationId,
    required String userId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    if (bytes.length > kMessageAttachmentMaxBytes) {
      throw StateError('Image must be 5 MB or smaller.');
    }
    final ext = _messageImageExtension(filename, contentType);
    if (ext == null) {
      throw StateError('Please choose a JPEG, PNG, or WebP image.');
    }
    final objectPath = '$conversationId/$userId/${_uuid.v4()}.$ext';
    await _supabase.client.storage
        .from(kMessageAttachmentBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return objectPath;
  }

  Future<void> deleteAttachment(String path) async {
    try {
      await _supabase.client.storage.from(kMessageAttachmentBucket).remove([
        path,
      ]);
    } catch (e) {
      debugPrint('ConversationService.deleteAttachment error ($e)');
    }
  }

  Future<String?> signedAttachmentUrl(String path) async {
    try {
      return await _supabase.client.storage
          .from(kMessageAttachmentBucket)
          .createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('ConversationService.signedAttachmentUrl error ($e)');
      return null;
    }
  }

  Future<String?> shareLookingFor({
    required String myId,
    required LookingForModel post,
    required List<String> sellerIds,
  }) async {
    final unique = sellerIds.toSet().where((id) => id != myId).toList();
    if (unique.isEmpty) return 'Select at least one seller you follow.';

    final body = lookingForShareBody(post);
    for (final sellerId in unique) {
      if (sellerId == post.buyerId) continue;
      final conversationId = await openOrCreate(myId: myId, otherId: sellerId);
      await sendMessage(
        conversationId: conversationId,
        senderId: myId,
        content: body,
        type: MessageType.lookingFor,
        lookingForPostId: post.id,
      );
    }
    return null;
  }

  Future<String> sendIHaveThis({
    required String sellerId,
    required LookingForModel post,
  }) async {
    if (sellerId == post.buyerId) {
      throw StateError('You cannot respond to your own request.');
    }
    final conversationId = await openOrCreate(
      myId: sellerId,
      otherId: post.buyerId,
    );
    await sendMessage(
      conversationId: conversationId,
      senderId: sellerId,
      content: lookingForIHaveThisBody(),
      type: MessageType.lookingFor,
      lookingForPostId: post.id,
    );
    return conversationId;
  }

  Future<List<FollowedSeller>> followedSellers(String myId) async {
    final followRows = await _supabase.client
        .from('follows')
        .select('following_id')
        .eq('follower_id', myId);
    final ids = (followRows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['following_id'] as String?)
        .whereType<String>()
        .where((id) => id != myId)
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];

    Map<String, Map<String, dynamic>> shops = {};
    try {
      final shopRows = await _supabase.client
          .from('seller_profiles')
          .select('seller_id, shop_name, is_approved')
          .inFilter('seller_id', ids);
      for (final row in shopRows as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final id = map['seller_id'] as String?;
        if (id != null) shops[id] = map;
      }
    } catch (e) {
      debugPrint('ConversationService seller_profiles error ($e)');
    }

    final sellerIds = shops.keys.toList();
    if (sellerIds.isEmpty) return const [];

    final profiles = await _profilesById(sellerIds);
    return sellerIds.map((id) {
      final profile = profiles[id];
      final shop = shops[id];
      final name =
          shop?['shop_name'] as String? ??
          profile?['full_name'] as String? ??
          profile?['username'] as String? ??
          'Seller';
      return FollowedSeller(
        id: id,
        name: name,
        avatar: profile?['avatar'] as String? ?? '',
        shopName: shop?['shop_name'] as String?,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Map<String, Map<String, dynamic>>> _profilesById(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final out = <String, Map<String, dynamic>>{};
    try {
      final rows = await _supabase.client
          .from('user_public_profiles')
          .select()
          .inFilter('user_id', ids);
      for (final p in rows as List<dynamic>) {
        final map = p as Map<String, dynamic>;
        final id = map['user_id'] as String?;
        if (id != null) out[id] = map;
      }
    } catch (e) {
      debugPrint('ConversationService profiles error ($e)');
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _productsById(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final out = <String, Map<String, dynamic>>{};
    try {
      final rows = await _supabase.client
          .from('products')
          .select('product_id, name')
          .inFilter('product_id', ids);
      for (final p in rows as List<dynamic>) {
        final map = p as Map<String, dynamic>;
        final id = map['product_id'] as String?;
        if (id != null) out[id] = map;
      }
    } catch (e) {
      debugPrint('ConversationService products error ($e)');
    }
    try {
      final imageRows = await _supabase.client
          .from('product_images')
          .select('product_id, image_url, is_primary, display_order')
          .inFilter('product_id', ids)
          .order('display_order', ascending: true);
      for (final raw in imageRows as List<dynamic>) {
        final map = raw as Map<String, dynamic>;
        final id = map['product_id'] as String?;
        if (id == null || !out.containsKey(id)) continue;
        final current = out[id]!;
        final isPrimary = map['is_primary'] == true;
        if (isPrimary || current['image_url'] == null) {
          current['image_url'] = map['image_url'];
        }
      }
    } catch (e) {
      debugPrint('ConversationService product_images error ($e)');
    }
    return out;
  }
}
