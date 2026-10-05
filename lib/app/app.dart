import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/presence_service.dart';
import '../core/services/shared_preferences_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_service.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/data_provider.dart';
import '../providers/following_shops_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/saved_items_provider.dart';
import '../providers/settings_provider.dart';

class ThriftlineApp extends StatelessWidget {
  const ThriftlineApp({
    super.key,
    required this.prefs,
    required this.router,
    required this.authProvider,
    required this.appProvider,
    required this.dataProvider,
    required this.notificationsProvider,
    required this.settingsProvider,
    required this.savedItemsProvider,
    required this.followingShopsProvider,
    required this.cartProvider,
    required this.supabaseService,
  });

  final SharedPreferencesService prefs;
  final GoRouter router;
  final AuthProvider authProvider;
  final AppProvider appProvider;
  final DataProvider dataProvider;
  final NotificationsProvider notificationsProvider;
  final SettingsProvider settingsProvider;
  final SavedItemsProvider savedItemsProvider;
  final FollowingShopsProvider followingShopsProvider;
  final CartProvider cartProvider;
  final SupabaseService supabaseService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferencesService>.value(value: prefs),
        Provider<SupabaseService>.value(value: supabaseService),
        Provider<AuthService>(create: (_) => AuthService(supabaseService)),
        Provider<PresenceService>(
          create: (_) => PresenceService(supabaseService),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ChangeNotifierProvider<DataProvider>.value(value: dataProvider),
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: notificationsProvider,
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<SavedItemsProvider>.value(
          value: savedItemsProvider,
        ),
        ChangeNotifierProvider<FollowingShopsProvider>.value(
          value: followingShopsProvider,
        ),
        ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
      ],
      child: _SessionBindings(
        child: MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
  }
}

/// Starts notification realtime, settings, saved items, and cart once a user is signed in.
class _SessionBindings extends StatefulWidget {
  const _SessionBindings({required this.child});
  final Widget child;

  @override
  State<_SessionBindings> createState() => _SessionBindingsState();
}

class _SessionBindingsState extends State<_SessionBindings>
    with WidgetsBindingObserver {
  String? _boundUserId;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _boundUserId != null) {
      context.read<PresenceService>().touch();
    }
  }

  void _bindSession(String? userId) {
    context.read<NotificationsProvider>().startForUser(userId);
    context.read<SettingsProvider>().loadForUser(userId);
    context.read<SavedItemsProvider>().startForUser(userId);
    context.read<FollowingShopsProvider>().startForUser(userId);
    context.read<CartProvider>().startForUser(userId);
    _presenceTimer?.cancel();
    if (userId == null) return;
    context.read<PresenceService>().touch();
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted) return;
      context.read<PresenceService>().touch();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == _boundUserId) return;
    _boundUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindSession(userId);
    });
  }

  void _syncNotificationAudience() {
    final auth = context.read<AuthProvider>();
    context.read<NotificationsProvider>().setAccountContext(
      mode: auth.activeAccount,
      hasSellerAccess: auth.user?.hasSellerAccess ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?.id;
    context.read<NotificationsProvider>().setAccountContext(
      mode: auth.activeAccount,
      hasSellerAccess: auth.user?.hasSellerAccess ?? false,
    );
    if (userId != _boundUserId) {
      _boundUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bindSession(userId);
        _syncNotificationAudience();
      });
    }
    return widget.child;
  }
}
