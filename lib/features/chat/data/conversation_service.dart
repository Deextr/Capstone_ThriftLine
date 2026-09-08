import 'package:flutter/foundation.dart';

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

class ConversationService {
  ConversationService(this._supabase);

  final SupabaseService _supabase;

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

    final others = await _profilesById(otherIds);
    return list.map((r) {
      final a = r['participant_a'] as String?;
      final b = r['participant_b'] as String?;
      final otherId = a == myId ? b : a;
      return ChatModel.fromSupabase(
        r,
        myId: myId,
        other: otherId != null ? others[otherId] : null,
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
    final others = otherId != null
        ? await _profilesById([otherId])
        : <String, Map<String, dynamic>>{};
    return ChatModel.fromSupabase(
      row,
      myId: myId,
      other: otherId != null ? others[otherId] : null,
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

  Future<String> openOrCreate({
    required String myId,
    required String otherId,
  }) async {
    if (myId == otherId) {
      throw StateError('Cannot open a conversation with yourself.');
    }
    final pair = orderedParticipantPair(myId, otherId);
    final row = await _supabase.client
        .from('conversations')
        .upsert({
          'participant_a': pair.a,
          'participant_b': pair.b,
        }, onConflict: 'participant_a,participant_b')
        .select('conversation_id')
        .single();
    return row['conversation_id'] as String;
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    MessageType type = MessageType.text,
    String? lookingForPostId,
    double? offerAmount,
  }) async {
    await _supabase.client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'message_type': type.dbValue,
      'looking_for_post_id': ?lookingForPostId,
      'offer_amount': ?offerAmount,
    });
    await _supabase.client
        .from('conversations')
        .update({
          'last_message': content,
          'last_message_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('conversation_id', conversationId);
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
}
