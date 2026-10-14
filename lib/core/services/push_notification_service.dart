import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../features/notifications/domain/notification_navigation.dart';
import '../../models/enums.dart';
import '../../models/notification_model.dart';
import '../../core/config/firebase_config.dart';
import '../../core/config/firebase_options.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/settings_provider.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = FirebaseConfig.options;
  if (options != null) {
    await Firebase.initializeApp(options: options);
  }
}

/// Registers FCM tokens, shows foreground alerts, and routes notification taps.
class PushNotificationService {
  PushNotificationService(this._supabase);

  final SupabaseService _supabase;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  GoRouter? _router;
  AuthProvider? _auth;
  NotificationsProvider? _notifications;
  SettingsProvider? _settings;

  String? _currentToken;
  String? _lastRegisterError;
  bool _initialized = false;
  bool _firebaseReady = false;
  Completer<void>? _initCompleter;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  bool get isFirebaseReady => _firebaseReady;
  bool get isFirebaseConfigured => FirebaseConfig.isConfigured;
  String? get lastRegisterError => _lastRegisterError;
  String? get currentTokenSuffix {
    final t = _currentToken;
    if (t == null || t.length < 8) return null;
    return t.substring(t.length - 8);
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidNotifications =>
      _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<bool> tryInitializeFirebase() async {
    if (kIsWeb) return false;
    try {
      final options =
          FirebaseConfig.options ?? DefaultFirebaseOptions.currentPlatform;
      if (options == null) {
        debugPrint(
          'PushNotificationService: Firebase env not configured (FIREBASE_* in .env)',
        );
        return false;
      }
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      return true;
    } catch (e) {
      debugPrint('PushNotificationService: Firebase init skipped: $e');
      return false;
    }
  }

  void bind({
    required GoRouter router,
    required AuthProvider auth,
    required NotificationsProvider notifications,
    required SettingsProvider settings,
  }) {
    _router = router;
    _auth = auth;
    _notifications = notifications;
    _settings = settings;
  }

  Future<void> ensureInitialized() async {
    if (kIsWeb || _initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      await initialize();
      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_stat_thriftline',
    );
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    await _androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        'thriftline_alerts',
        'ThriftLine alerts',
        description: 'Order, message, and marketplace updates',
        importance: Importance.high,
      ),
    );

    _firebaseReady = await tryInitializeFirebase();
    if (!_firebaseReady) return;

    _foregroundSub = FirebaseMessaging.onMessage.listen(_showForegroundAlert);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteOpen);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleRemoteOpen(initial);
      });
    }

    final uid = _auth?.user?.id;
    if (uid != null) {
      unawaited(syncRegistrationForUser(uid));
    }
  }

  Future<PushRegistrationDiagnostics> diagnostics({
    required bool appPushEnabled,
  }) async {
    await ensureInitialized();
    final perm = await permissionSnapshot();
    return PushRegistrationDiagnostics(
      firebaseConfigured: isFirebaseConfigured,
      firebaseInitialized: _firebaseReady,
      osPermissionGranted: perm.osGranted,
      appPushEnabled: appPushEnabled,
      hasDeviceToken: _currentToken != null,
      tokenSuffix: currentTokenSuffix,
      lastError: _lastRegisterError,
    );
  }

  Future<NotificationPermissionSnapshot> permissionSnapshot() async {
    if (kIsWeb) {
      return NotificationPermissionSnapshot.unavailable();
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled =
          await _androidNotifications?.areNotificationsEnabled() ?? false;
      return NotificationPermissionSnapshot(
        osGranted: enabled,
        canRequestAgain: !enabled,
      );
    }
    if (!_firebaseReady) {
      return NotificationPermissionSnapshot.unavailable();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      return NotificationPermissionSnapshot(
        osGranted: authorized,
        canRequestAgain: settings.authorizationStatus ==
            AuthorizationStatus.notDetermined,
      );
    }
    return NotificationPermissionSnapshot.unavailable();
  }

  Future<bool> requestOsPermission({bool showRationale = false}) async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (showRationale) {
        // Caller shows in-app copy before this runs.
      }
      await _androidNotifications?.requestNotificationsPermission();
      return await _androidNotifications?.areNotificationsEnabled() ?? false;
    }
    if (!_firebaseReady) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }
    return false;
  }

  /// Opens this app's page in system settings (notification toggles live there).
  Future<void> openOsAppSettings() async {
    const packageName = 'com.example.thriftline';
    if (defaultTargetPlatform == TargetPlatform.android) {
      final uri = Uri.parse(
        'intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;'
        'data=package:$packageName;end',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final uri = Uri.parse('app-settings:');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<bool> syncRegistrationForUser(String? userId) async {
    _lastRegisterError = null;
    await ensureInitialized();
    if (!_firebaseReady || userId == null || userId.isEmpty) {
      await revokeCurrentDeviceToken();
      if (!_firebaseReady && userId != null && userId.isNotEmpty) {
        _lastRegisterError =
            'Firebase is not configured. Add FIREBASE_* keys to .env and restart the app.';
      }
      return false;
    }
    final settings = _settings;
    final auth = _auth;
    if (settings == null || auth == null) {
      _lastRegisterError = 'App session not ready.';
      return false;
    }
    if (!settings.pushFor(auth.activeAccount)) {
      await revokeCurrentDeviceToken();
      return false;
    }
    final perm = await permissionSnapshot();
    if (!perm.osGranted) {
      _lastRegisterError = 'Allow notifications in device settings first.';
      return false;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      _lastRegisterError =
          'FCM did not return a device token. Check Firebase setup and google-services.json.';
      return false;
    }
    _currentToken = token;
    final ok = await _registerToken(token);
    if (!ok) return false;

    _tokenRefreshSub ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((next) async {
      _currentToken = next;
      final uid = _auth?.user?.id;
      if (uid != null) await _registerToken(next);
    });
    return true;
  }

  Future<void> revokeCurrentDeviceToken() async {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    final token = _currentToken;
    _currentToken = null;
    if (token == null || token.isEmpty) return;
    try {
      await _supabase.client.rpc(
        'revoke_push_device_token',
        params: {'p_device_token': token},
      );
    } catch (e) {
      debugPrint('PushNotificationService.revoke error: $e');
    }
  }

  Future<bool> _registerToken(String token) async {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
    try {
      await _supabase.client.rpc(
        'register_push_device_token',
        params: {
          'p_device_token': token,
          'p_platform': platform,
          'p_app_version': null,
        },
      );
      _lastRegisterError = null;
      return true;
    } catch (e) {
      _lastRegisterError = 'Could not save device token to Supabase.';
      debugPrint('PushNotificationService.register error: $e');
      return false;
    }
  }

  Future<void> _showForegroundAlert(RemoteMessage message) async {
    final settings = _settings;
    final auth = _auth;
    if (settings == null || auth == null) return;
    if (!settings.pushFor(auth.activeAccount)) return;

    final notification = message.notification;
    final data = message.data;
    final title =
        notification?.title ??
        data['title']?.toString() ??
        'ThriftLine';
    final body =
        notification?.body ??
        data['body']?.toString() ??
        '';
    if (body.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'thriftline_alerts',
        'ThriftLine alerts',
        channelDescription: 'Order, message, and marketplace updates',
        icon: '@drawable/ic_stat_thriftline',
        color: AppColors.primary,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: details,
      payload: message.data['notification_id']?.toString(),
    );
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final id = response.payload?.trim();
    if (id == null || id.isEmpty) return;
    _openFromPushData({'notification_id': id});
  }

  void _handleRemoteOpen(RemoteMessage message) {
    _openFromPushData(message.data);
  }

  void _openFromPushData(Map<String, dynamic> data) {
    final router = _router;
    final auth = _auth;
    final notifications = _notifications;
    if (router == null || auth == null) return;

    final notificationId = '${data['notification_id'] ?? ''}'.trim();
    NotificationModel? model;
    if (notificationId.isNotEmpty && notifications != null) {
      model = notifications.findById(notificationId);
    }

    model ??= NotificationModel(
      id: notificationId,
      userId: auth.user?.id ?? '',
      type: NotificationType.fromString('${data['type'] ?? 'system'}'),
      audience: NotificationAudience.fromString('${data['audience'] ?? ''}'),
      title: '',
      body: '',
      createdAt: DateTime.now(),
      data: {
        for (final e in data.entries)
          if (e.value != null) e.key: '${e.value}',
      },
    );

    if (notificationId.isNotEmpty) {
      unawaited(notifications?.markRead(notificationId));
    }
    openNotification(
      router,
      notification: model,
      activeAccount: auth.activeAccount,
    );
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
  }
}

class NotificationPermissionSnapshot {
  const NotificationPermissionSnapshot({
    required this.osGranted,
    required this.canRequestAgain,
    this.unavailable = false,
  });

  factory NotificationPermissionSnapshot.unavailable() =>
      const NotificationPermissionSnapshot(
        osGranted: false,
        canRequestAgain: false,
        unavailable: true,
      );

  final bool osGranted;
  final bool canRequestAgain;
  final bool unavailable;
}

class PushRegistrationDiagnostics {
  const PushRegistrationDiagnostics({
    required this.firebaseConfigured,
    required this.firebaseInitialized,
    required this.osPermissionGranted,
    required this.appPushEnabled,
    required this.hasDeviceToken,
    this.tokenSuffix,
    this.lastError,
  });

  final bool firebaseConfigured;
  final bool firebaseInitialized;
  final bool osPermissionGranted;
  final bool appPushEnabled;
  final bool hasDeviceToken;
  final String? tokenSuffix;
  final String? lastError;

  bool get readyForPush =>
      firebaseInitialized &&
      osPermissionGranted &&
      appPushEnabled &&
      hasDeviceToken;
}
