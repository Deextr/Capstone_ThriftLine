import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/chat/data/conversation_service.dart';
import 'package:thriftline/models/chat_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/looking_for_model.dart';
import 'package:thriftline/models/message_model.dart';

void main() {
  group('conversation pairing', () {
    test('orders participant ids so a is always less than b', () {
      final pair = orderedParticipantPair(
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      expect(pair.a.compareTo(pair.b), lessThan(0));
    });

    test('general and product threads are distinct keys', () {
      final pair = orderedParticipantPair('buyer', 'seller');
      expect((
        pair.a,
        pair.b,
        null,
      ), isNot(equals((pair.a, pair.b, 'product-1'))));
      expect((
        pair.a,
        pair.b,
        'product-1',
      ), isNot(equals((pair.a, pair.b, 'product-2'))));
    });
  });

  group('unread indicator', () {
    final sentAt = DateTime.utc(2026, 9, 10, 12);

    test('empty preview is not unread', () {
      expect(
        conversationUnreadIndicator(
          lastMessageAt: sentAt,
          myLastReadAt: null,
          lastMessage: '',
        ),
        0,
      );
    });

    test('never opened thread with a message is unread', () {
      expect(
        conversationUnreadIndicator(
          lastMessageAt: sentAt,
          myLastReadAt: null,
          lastMessage: 'Hello',
        ),
        1,
      );
    });

    test('own send at last_read is not unread', () {
      expect(
        conversationUnreadIndicator(
          lastMessageAt: sentAt,
          myLastReadAt: sentAt,
          lastMessage: 'Hello',
        ),
        0,
      );
    });

    test('later incoming message is unread', () {
      expect(
        conversationUnreadIndicator(
          lastMessageAt: sentAt.add(const Duration(minutes: 1)),
          myLastReadAt: sentAt,
          lastMessage: 'Hi',
        ),
        1,
      );
    });
  });

  group('ChatModel.fromSupabase', () {
    test('computes unread from last_read_at of the current user', () {
      final chat = ChatModel.fromSupabase(
        {
          'conversation_id': 'c1',
          'participant_a': 'aaa',
          'participant_b': 'bbb',
          'last_message': 'New note',
          'last_message_at': '2026-09-10T12:01:00Z',
          'last_read_at_a': '2026-09-10T12:00:00Z',
          'last_read_at_b': '2026-09-10T12:01:00Z',
          'product_id': 'p1',
        },
        myId: 'aaa',
        other: {'full_name': 'Seller B', 'avatar': ''},
        product: {
          'product_id': 'p1',
          'name': 'Vintage jacket',
          'image_url': 'https://example.com/j.jpg',
        },
      );
      expect(chat.hasUnread, isTrue);
      expect(chat.unreadCount, 1);
      expect(chat.productId, 'p1');
      expect(chat.productTitle, 'Vintage jacket');
      expect(chat.otherName, 'Seller B');
    });

    test('recipient who already read is not unread', () {
      final chat = ChatModel.fromSupabase(
        {
          'conversation_id': 'c1',
          'participant_a': 'aaa',
          'participant_b': 'bbb',
          'last_message': 'New note',
          'last_message_at': '2026-09-10T12:01:00Z',
          'last_read_at_a': '2026-09-10T12:00:00Z',
          'last_read_at_b': '2026-09-10T12:01:00Z',
        },
        myId: 'bbb',
        other: {'full_name': 'Buyer A'},
      );
      expect(chat.hasUnread, isFalse);
    });
  });

  group('messages', () {
    MessageModel message({
      required String id,
      required DateTime createdAt,
      String content = 'x',
    }) {
      return MessageModel(
        id: id,
        chatId: 'c1',
        senderId: 'aaa',
        content: content,
        createdAt: createdAt,
      );
    }

    test('upsertMessages dedupes by id and sorts by created_at', () {
      final first = message(
        id: 'm1',
        createdAt: DateTime.utc(2026, 9, 10, 12),
        content: 'one',
      );
      final second = message(
        id: 'm2',
        createdAt: DateTime.utc(2026, 9, 10, 12, 1),
        content: 'two',
      );
      final lateFirst = message(
        id: 'm1',
        createdAt: DateTime.utc(2026, 9, 10, 11, 59),
        content: 'one-updated',
      );
      final outOfOrder = upsertMessages(
        upsertMessages([second], first),
        lateFirst,
      );
      expect(outOfOrder.map((m) => m.id), ['m1', 'm2']);
      expect(outOfOrder.first.content, 'one-updated');
    });

    test('image rows keep attachment_path', () {
      final msg = MessageModel.fromSupabase({
        'message_id': 'm9',
        'conversation_id': 'c1',
        'sender_id': 'aaa',
        'content': '',
        'message_type': 'image',
        'attachment_path': 'c1/aaa/file.jpg',
        'created_at': '2026-09-10T12:00:00Z',
      });
      expect(msg.type, MessageType.image);
      expect(msg.attachmentPath, 'c1/aaa/file.jpg');
    });

    test('attachment path must start with conversation and sender', () {
      expect(
        isMessageAttachmentPathFor(
          conversationId: 'c1',
          userId: 'u1',
          path: 'c1/u1/abc.jpg',
        ),
        isTrue,
      );
      expect(
        isMessageAttachmentPathFor(
          conversationId: 'c1',
          userId: 'u1',
          path: 'c2/u1/abc.jpg',
        ),
        isFalse,
      );
    });
  });

  group('Looking For copy', () {
    test('share body keeps the original request title', () {
      final post = LookingForModel.fromSupabase(
        {
          'post_id': 'lf1',
          'user_id': 'u1',
          'title': 'Black Nike jacket',
          'preferred_size': 'M',
          'status': 'open',
          'created_at': '2026-09-01T00:00:00Z',
        },
        buyer: {'full_name': 'Buyer 1'},
      );
      expect(lookingForShareBody(post), contains('Buyer 1 is looking for:'));
      expect(lookingForShareBody(post), contains('Black Nike jacket'));
      expect(lookingForIHaveThisBody(), contains('I have an item'));
    });
  });
}
