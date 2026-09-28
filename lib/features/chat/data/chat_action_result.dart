class ChatActionResult {
  const ChatActionResult.ok({this.conversationId}) : error = null;
  const ChatActionResult.error(this.error) : conversationId = null;

  final String? error;
  final String? conversationId;
  bool get isOk => error == null;
}
