import 'dart:convert';
import 'dart:html' as html;

typedef AdminPortalTabMessageHandler =
    void Function(AdminPortalTabMessage message);

enum AdminPortalTabMessageKind { activity, signedOut }

class AdminPortalTabMessage {
  const AdminPortalTabMessage._(this.kind, {this.activityMs, this.nonce});

  const AdminPortalTabMessage.activity(int activityMs)
    : this._(AdminPortalTabMessageKind.activity, activityMs: activityMs);

  const AdminPortalTabMessage.signedOut(int nonce)
    : this._(AdminPortalTabMessageKind.signedOut, nonce: nonce);

  final AdminPortalTabMessageKind kind;
  final int? activityMs;
  final int? nonce;
}

class AdminPortalTabBroadcast {
  static const _channelName = 'thriftline_admin_portal_session_v1';

  html.BroadcastChannel? _channel;
  AdminPortalTabMessageHandler? _handler;

  void install({required AdminPortalTabMessageHandler onMessage}) {
    _handler = onMessage;
    _channel?.close();
    _channel = html.BroadcastChannel(_channelName);
    _channel!.onMessage.listen((event) {
      final handler = _handler;
      if (handler == null) return;
      final parsed = _parse(event.data);
      if (parsed != null) handler(parsed);
    });
  }

  void notifyActivity(int activityMs) {
    _post({'type': 'activity', 'ms': activityMs});
  }

  void notifySignedOut(int nonce) {
    _post({'type': 'signed_out', 'nonce': nonce});
  }

  void dispose() {
    _channel?.close();
    _channel = null;
    _handler = null;
  }

  void _post(Map<String, Object> payload) {
    try {
      _channel ??= html.BroadcastChannel(_channelName);
      _channel!.postMessage(jsonEncode(payload));
    } catch (_) {
      // Best-effort cross-tab sync; Supabase sign-out remains the source of truth.
    }
  }

  AdminPortalTabMessage? _parse(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final type = decoded['type'];
      if (type == 'activity' && decoded['ms'] is num) {
        return AdminPortalTabMessage.activity((decoded['ms'] as num).toInt());
      }
      if (type == 'signed_out' && decoded['nonce'] is num) {
        return AdminPortalTabMessage.signedOut(
          (decoded['nonce'] as num).toInt(),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
