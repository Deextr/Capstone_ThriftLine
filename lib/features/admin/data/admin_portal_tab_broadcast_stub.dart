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
  void install({required AdminPortalTabMessageHandler onMessage}) {}

  void notifyActivity(int activityMs) {}

  void notifySignedOut(int nonce) {}

  void dispose() {}
}
