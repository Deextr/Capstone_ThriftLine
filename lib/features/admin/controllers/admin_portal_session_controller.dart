import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/shared_preferences_service.dart';
import '../../../providers/auth_provider.dart';
import '../data/admin_portal_session_service.dart';
import '../data/admin_portal_tab_broadcast.dart';
import '../domain/admin_portal_session_policy.dart';

/// Central Admin Web Portal session policy: inactivity timeout and cross-tab sign-out.
class AdminPortalSessionController extends ChangeNotifier {
  AdminPortalSessionController({
    required SharedPreferencesService prefs,
    required AuthProvider auth,
    AdminPortalSessionService? portalSession,
    AdminPortalTabBroadcast? tabBroadcast,
    Duration inactivityTimeout = adminPortalInactivityTimeout,
    Duration serverActivitySyncInterval = const Duration(seconds: 30),
  }) : _prefs = prefs,
       _auth = auth,
       _portalSession = portalSession,
       _tabBroadcast = tabBroadcast ?? AdminPortalTabBroadcast(),
       _inactivityTimeout = inactivityTimeout,
       _serverActivitySyncInterval = serverActivitySyncInterval;

  final SharedPreferencesService _prefs;
  final AuthProvider _auth;
  final AdminPortalSessionService? _portalSession;
  final AdminPortalTabBroadcast _tabBroadcast;
  final Duration _inactivityTimeout;
  final Duration _serverActivitySyncInterval;

  Timer? _deadlineTimer;
  int _lastPersistedActivityMs = 0;
  int _lastServerTouchMs = 0;
  int _lastSeenLogoutNonce = 0;
  int _timerGeneration = 0;
  bool _monitoring = false;
  bool _expiring = false;
  bool _externalSignOutInProgress = false;
  bool _sawAuthenticatedSession = false;

  bool get isMonitoring => _monitoring;

  void init() {
    _lastSeenLogoutNonce = _prefs.adminPortalLogoutNonce;
    _sawAuthenticatedSession = shouldMonitorAdminPortalSession(_auth);
    _tabBroadcast.install(onMessage: _handleTabMessage);
    _auth.addListener(_syncMonitoring);
    _syncMonitoring();
  }

  @override
  void dispose() {
    _auth.removeListener(_syncMonitoring);
    _stopMonitoring(clearClock: false);
    _tabBroadcast.dispose();
    super.dispose();
  }

  void onUserActivity() {
    if (!_monitoring || _expiring) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final throttleMs = adminPortalActivityPersistThrottle.inMilliseconds;
    if (now - _lastPersistedActivityMs < throttleMs) {
      _scheduleDeadlineFrom(_lastPersistedActivityMs);
      return;
    }
    _lastPersistedActivityMs = now;
    unawaited(_prefs.setAdminPortalLastActivityMs(now));
    _tabBroadcast.notifyActivity(now);
    _scheduleDeadlineFrom(now);
    _syncServerActivity(now);
  }

  Future<void> expireDueToInactivity() =>
      _expireSession(notice: adminPortalInactivityLogoutMessage);

  Future<void> publishSignedOutToOtherTabs() async {
    final nonce = await _prefs.bumpAdminPortalLogoutNonce();
    _lastSeenLogoutNonce = nonce;
    _tabBroadcast.notifySignedOut(nonce);
  }

  /// Suppresses inactivity handling while the user confirms sign-out.
  void beginManualSignOut() {
    _expiring = true;
    _stopMonitoring(clearClock: true);
    unawaited(_prefs.clearAdminPortalLoginNotice());
  }

  void endManualSignOut() {
    _expiring = false;
  }

  /// Clears a leftover timeout banner after a successful sign-in.
  Future<void> clearStaleLoginNotice() => _prefs.clearAdminPortalLoginNotice();

  void _syncMonitoring() {
    final shouldMonitor = shouldMonitorAdminPortalSession(_auth);
    var changed = false;
    if (shouldMonitor) {
      if (!_monitoring) {
        final reuseStoredActivity = _sawAuthenticatedSession;
        _sawAuthenticatedSession = true;
        if (!reuseStoredActivity) {
          unawaited(_prefs.clearAdminPortalLoginNotice());
        }
        _startMonitoring(reuseStoredActivity: reuseStoredActivity);
        changed = true;
      }
    } else {
      _sawAuthenticatedSession = false;
      if (_monitoring) {
        _stopMonitoring(clearClock: true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _startMonitoring({required bool reuseStoredActivity}) {
    _monitoring = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startMs = resolveAdminPortalMonitorStartMs(
      storedActivityMs: _prefs.adminPortalLastActivityMs,
      nowMs: now,
      reuseStoredActivity: reuseStoredActivity,
    );
    _lastPersistedActivityMs = startMs;
    unawaited(_prefs.setAdminPortalLastActivityMs(startMs));
    _scheduleDeadlineFrom(startMs);
    unawaited(
      _bootstrapServerSession(reuseStoredActivity: reuseStoredActivity),
    );
  }

  void _stopMonitoring({required bool clearClock}) {
    _monitoring = false;
    _timerGeneration++;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    if (clearClock) {
      _lastPersistedActivityMs = 0;
      unawaited(_prefs.setAdminPortalLastActivityMs(0));
    }
  }

  void _scheduleDeadlineFrom(int lastActivityMs) {
    _deadlineTimer?.cancel();
    if (!_monitoring) return;

    final generation = ++_timerGeneration;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastActivityMs;
    final remainingMs = _inactivityTimeout.inMilliseconds - elapsedMs;
    if (remainingMs <= 0) {
      unawaited(expireDueToInactivity());
      return;
    }
    _deadlineTimer = Timer(Duration(milliseconds: remainingMs), () {
      if (generation != _timerGeneration || !_monitoring || _expiring) return;
      unawaited(expireDueToInactivity());
    });
  }

  Future<void> _expireSession({required String notice}) async {
    if (_expiring || !shouldMonitorAdminPortalSession(_auth)) return;
    _expiring = true;
    _stopMonitoring(clearClock: true);
    try {
      await _prefs.setAdminPortalLoginNotice(notice);
      await _portalSession?.revoke(reason: 'idle');
      await publishSignedOutToOtherTabs();
      await _auth.logout();
    } finally {
      _expiring = false;
    }
  }

  void _handleTabMessage(AdminPortalTabMessage message) {
    if (message.kind == AdminPortalTabMessageKind.activity) {
      final ms = message.activityMs;
      if (ms == null || !_monitoring) return;
      if (ms <= _lastPersistedActivityMs) return;
      _lastPersistedActivityMs = ms;
      _scheduleDeadlineFrom(ms);
      _syncServerActivity(ms);
      return;
    }
    if (message.kind == AdminPortalTabMessageKind.signedOut) {
      final nonce = message.nonce;
      if (nonce == null || nonce == _lastSeenLogoutNonce) return;
      _lastSeenLogoutNonce = nonce;
      if (!_auth.isAuthenticated || _expiring || _externalSignOutInProgress) {
        return;
      }
      _externalSignOutInProgress = true;
      _stopMonitoring(clearClock: true);
      unawaited(() async {
        try {
          await _auth.logout();
        } finally {
          _externalSignOutInProgress = false;
        }
      }());
    }
  }

  Future<void> revokeServerSession({String reason = 'sign_out'}) async {
    await _portalSession?.revoke(reason: reason);
  }

  Future<void> _bootstrapServerSession({
    required bool reuseStoredActivity,
  }) async {
    final portal = _portalSession;
    if (portal == null) return;
    var ok = reuseStoredActivity ? await portal.touch() : await portal.begin();
    if (!ok &&
        reuseStoredActivity &&
        adminPortalRemainingMs(
              lastActivityMs: _lastPersistedActivityMs,
              nowMs: DateTime.now().millisecondsSinceEpoch,
              timeout: _inactivityTimeout,
            ) >
            0) {
      ok = await portal.begin();
    }
    if (!ok && _monitoring && shouldMonitorAdminPortalSession(_auth)) {
      await _expireSession(notice: adminPortalInactivityLogoutMessage);
    } else if (ok) {
      _lastServerTouchMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void _syncServerActivity(int activityMs) {
    final portal = _portalSession;
    if (portal == null || !_monitoring) return;
    if (activityMs - _lastServerTouchMs <
        _serverActivitySyncInterval.inMilliseconds) {
      return;
    }
    _lastServerTouchMs = activityMs;
    unawaited(() async {
      final ok = await portal.touch();
      if (!ok && _monitoring && shouldMonitorAdminPortalSession(_auth)) {
        await _expireSession(notice: adminPortalInactivityLogoutMessage);
      }
    }());
  }
}

@visibleForTesting
int adminPortalRemainingMs({
  required int lastActivityMs,
  required int nowMs,
  Duration timeout = adminPortalInactivityTimeout,
}) {
  final remaining = timeout.inMilliseconds - (nowMs - lastActivityMs);
  return remaining < 0 ? 0 : remaining;
}
