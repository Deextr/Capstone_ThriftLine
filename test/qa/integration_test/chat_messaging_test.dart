import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/features/chat/data/chat_action_result.dart';
import 'package:thriftline/models/chat_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/message_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Chat compose harness simulating the real-time messaging input.
class _ChatComposeHarness extends StatefulWidget {
  const _ChatComposeHarness({
    required this.otherUserName,
    required this.productTitle,
    required this.onSend,
  });

  final String otherUserName;
  final String? productTitle;
  final void Function(String content, MessageType type, double? offerAmount)
      onSend;

  @override
  State<_ChatComposeHarness> createState() => _ChatComposeHarnessState();
}

class _ChatComposeHarnessState extends State<_ChatComposeHarness> {
  final _messageController = TextEditingController();
  final _offerController = TextEditingController();
  MessageType _selectedType = MessageType.text;
  String? _sendError;
  final List<Map<String, dynamic>> _sentMessages = [];

  @override
  void dispose() {
    _messageController.dispose();
    _offerController.dispose();
    super.dispose();
  }

  void _send() {
    setState(() => _sendError = null);

    final content = _messageController.text.trim();
    if (content.isEmpty && _selectedType == MessageType.text) {
      setState(() => _sendError = 'Message cannot be empty.');
      return;
    }

    double? offerAmount;
    if (_selectedType == MessageType.offer) {
      offerAmount = double.tryParse(_offerController.text.trim());
      if (offerAmount == null || offerAmount <= 0) {
        setState(() => _sendError = 'Enter a valid offer amount.');
        return;
      }
    }

    _sentMessages.add({
      'content': content,
      'type': _selectedType.name,
      'offer': offerAmount,
    });

    widget.onSend(content, _selectedType, offerAmount);

    setState(() {
      _messageController.clear();
      _offerController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        bottom: widget.productTitle != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Re: ${widget.productTitle}',
                    key: const Key('chat-product-context'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _sentMessages.length,
                itemBuilder: (_, i) {
                  final msg = _sentMessages[i];
                  return ListTile(
                    key: Key('sent-msg-$i'),
                    title: Text(msg['content'] as String),
                    subtitle: Text(msg['type'] as String),
                    trailing: msg['offer'] != null
                        ? Text('₱${msg['offer']}')
                        : null,
                  );
                },
              ),
            ),
            Row(
              children: [
                ChoiceChip(
                  key: const Key('chat-type-text'),
                  label: const Text('Text'),
                  selected: _selectedType == MessageType.text,
                  onSelected: (_) =>
                      setState(() => _selectedType = MessageType.text),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('chat-type-offer'),
                  label: const Text('Offer'),
                  selected: _selectedType == MessageType.offer,
                  onSelected: (_) =>
                      setState(() => _selectedType = MessageType.offer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedType == MessageType.offer)
              ThriftTextField(
                key: const Key('chat-offer-input'),
                label: 'Offer Amount (₱)',
                controller: _offerController,
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: 8),
            ThriftTextField(
              key: const Key('chat-message-input'),
              label: 'Message',
              controller: _messageController,
              error: _sendError,
            ),
            const SizedBox(height: 12),
            ThriftButton(
              key: const Key('chat-send-button'),
              label: 'Send',
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

Finder _chatInput(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(TextFormField),
    );

void chatMessagingIntegrationTests() {
  qaGroup('Chat & Messaging Integration Flow', () {
    qaIntegrationTest(
        'buyer-to-seller conversation with text & offer messages', (
      tester,
    ) async {
      String? lastContent;
      MessageType? lastType;
      double? lastOffer;

      await tester.pumpWidget(
        MaterialApp(
          home: _ChatComposeHarness(
            otherUserName: 'Ukay Thrift Shop',
            productTitle: 'Vintage Denim Jacket',
            onSend: (content, type, offer) {
              lastContent = content;
              lastType = type;
              lastOffer = offer;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify product context header
      expect(find.text('Re: Vintage Denim Jacket'), findsOneWidget);
      expect(find.text('Ukay Thrift Shop'), findsOneWidget);

      // 1. Try sending empty text message
      await tester.ensureVisible(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('Message cannot be empty.'), findsOneWidget);
      expect(lastContent, isNull);

      // 2. Send a valid text message
      await tester.enterText(
          _chatInput('chat-message-input'), 'Is this still available?');
      await tester.ensureVisible(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      expect(lastContent, 'Is this still available?');
      expect(lastType, MessageType.text);
      expect(lastOffer, isNull);

      // 3. Switch to offer mode and send an offer
      await tester.tap(find.byKey(const Key('chat-type-offer')));
      await tester.pumpAndSettle();

      // Try invalid offer first
      await tester.enterText(_chatInput('chat-offer-input'), 'abc');
      await tester.enterText(
          _chatInput('chat-message-input'), 'Would you take this?');
      await tester.ensureVisible(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid offer amount.'), findsOneWidget);

      // Valid offer
      await tester.enterText(_chatInput('chat-offer-input'), '700');
      await tester.enterText(
          _chatInput('chat-message-input'), 'Can you do 700?');
      await tester.ensureVisible(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      expect(lastContent, 'Can you do 700?');
      expect(lastType, MessageType.offer);
      expect(lastOffer, 700.0);
    });

    qaIntegrationTest(
        'ChatModel.fromSupabase parses conversation with unread indicator', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      final fiveMinAgo = now.subtract(const Duration(minutes: 5));
      final tenMinAgo = now.subtract(const Duration(minutes: 10));

      // Buyer (participant_a) last read 10 min ago, last message was 5 min ago
      final chat = ChatModel.fromSupabase(
        {
          'conversation_id': 'conv-001',
          'participant_a': 'buyer-1',
          'participant_b': 'seller-2',
          'last_message': 'Item is available!',
          'last_message_at': fiveMinAgo.toIso8601String(),
          'last_read_at_a': tenMinAgo.toIso8601String(),
          'last_read_at_b': fiveMinAgo.toIso8601String(),
          'product_id': 'prod-jacket-1',
          'product': {
            'product_id': 'prod-jacket-1',
            'name': 'Vintage Denim Jacket',
          },
        },
        myId: 'buyer-1',
        other: {
          'full_name': 'Ukay Thrift Shop',
          'username': 'ukay_thrift',
          'avatar': 'https://example.com/avatar.jpg',
        },
      );

      expect(chat.id, 'conv-001');
      expect(chat.otherName, 'Ukay Thrift Shop');
      expect(chat.productTitle, 'Vintage Denim Jacket');
      expect(chat.hasUnread, isTrue);
      expect(chat.unreadCount, 1);
      expect(chat.titleFor('buyer-1'), 'Ukay Thrift Shop');
      expect(chat.avatarFor('buyer-1'), 'https://example.com/avatar.jpg');

      // Now simulate buyer has caught up reading
      final caughtUpChat = ChatModel.fromSupabase(
        {
          'conversation_id': 'conv-001',
          'participant_a': 'buyer-1',
          'participant_b': 'seller-2',
          'last_message': 'Item is available!',
          'last_message_at': fiveMinAgo.toIso8601String(),
          'last_read_at_a': now.toIso8601String(), // caught up
          'last_read_at_b': fiveMinAgo.toIso8601String(),
        },
        myId: 'buyer-1',
        other: {'full_name': 'Ukay Thrift Shop'},
      );

      expect(caughtUpChat.hasUnread, isFalse);
      expect(caughtUpChat.unreadCount, 0);
    });

    qaIntegrationTest(
        'MessageModel.fromSupabase handles text, offer, and lookingFor types', (
      tester,
    ) async {
      // Standard text message
      final textMsg = MessageModel.fromSupabase({
        'message_id': 'msg-001',
        'conversation_id': 'conv-001',
        'sender_id': 'buyer-1',
        'content': 'Hello, is this available?',
        'created_at': DateTime.now().toIso8601String(),
        'message_type': 'text',
      });

      expect(textMsg.type, MessageType.text);
      expect(textMsg.content, 'Hello, is this available?');
      expect(textMsg.isSentBy('buyer-1'), isTrue);
      expect(textMsg.isSentBy('seller-2'), isFalse);
      expect(textMsg.offerAmount, isNull);

      // Offer message
      final offerMsg = MessageModel.fromSupabase({
        'message_id': 'msg-002',
        'conversation_id': 'conv-001',
        'sender_id': 'buyer-1',
        'content': 'Can you do 700?',
        'created_at': DateTime.now().toIso8601String(),
        'message_type': 'offer',
        'offer_amount': 700.0,
      });

      expect(offerMsg.type, MessageType.offer);
      expect(offerMsg.offerAmount, 700.0);

      // Looking-for message with embedded post data
      final lookingForMsg = MessageModel.fromSupabase({
        'message_id': 'msg-003',
        'conversation_id': 'conv-001',
        'sender_id': 'seller-2',
        'content': 'I have something like this!',
        'created_at': DateTime.now().toIso8601String(),
        'message_type': 'looking_for',
        'looking_for_post': {
          'post_id': 'lf-post-001',
          'title': 'ISO: Vintage Band Tees',
          'reference_image_url': 'https://example.com/ref.jpg',
        },
      });

      expect(lookingForMsg.type, MessageType.lookingFor);
      expect(lookingForMsg.lookingForPostId, 'lf-post-001');
      expect(lookingForMsg.lookingForTitle, 'ISO: Vintage Band Tees');
      expect(lookingForMsg.lookingForImageUrl, 'https://example.com/ref.jpg');
    });

    qaIntegrationTest(
        'ChatActionResult reports success and error states correctly', (
      tester,
    ) async {
      const okResult =
          ChatActionResult.ok(conversationId: 'conv-new-001');
      expect(okResult.isOk, isTrue);
      expect(okResult.conversationId, 'conv-new-001');
      expect(okResult.error, isNull);

      const errorResult = ChatActionResult.error(
          'You can only message sellers of active listings.');
      expect(errorResult.isOk, isFalse);
      expect(errorResult.error,
          'You can only message sellers of active listings.');
      expect(errorResult.conversationId, isNull);
    });

    qaIntegrationTest(
        'conversationUnreadIndicator edge cases for empty and null messages', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      final before = now.subtract(const Duration(minutes: 1));

      // Empty last message → no unread
      expect(
        conversationUnreadIndicator(
          lastMessageAt: now,
          myLastReadAt: before,
          lastMessage: '',
        ),
        0,
      );

      // Whitespace-only last message → no unread
      expect(
        conversationUnreadIndicator(
          lastMessageAt: now,
          myLastReadAt: before,
          lastMessage: '   ',
        ),
        0,
      );

      // Null lastRead → unread
      expect(
        conversationUnreadIndicator(
          lastMessageAt: now,
          myLastReadAt: null,
          lastMessage: 'Hi!',
        ),
        1,
      );

      // lastRead is after lastMessage → no unread
      expect(
        conversationUnreadIndicator(
          lastMessageAt: before,
          myLastReadAt: now,
          lastMessage: 'Hi!',
        ),
        0,
      );
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    chatMessagingIntegrationTests();
  });
}
