import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/shared_preferences_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_service.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/data_provider.dart';
import '../providers/notifications_provider.dart';
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
    required this.supabaseService,
  });

  final SharedPreferencesService prefs;
  final GoRouter router;
  final AuthProvider authProvider;
  final AppProvider appProvider;
  final DataProvider dataProvider;
  final NotificationsProvider notificationsProvider;
  final SettingsProvider settingsProvider;
  final SupabaseService supabaseService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferencesService>.value(value: prefs),
        Provider<SupabaseService>.value(value: supabaseService),
        Provider<AuthService>(
          create: (_) => AuthService(supabaseService),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ChangeNotifierProvider<DataProvider>.value(value: dataProvider),
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: notificationsProvider,
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<CartProvider>(create: (_) => CartProvider()),
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

/// Starts notification realtime and settings once a user is signed in.
class _SessionBindings extends StatefulWidget {
  const _SessionBindings({required this.child});
  final Widget child;

  @override
  State<_SessionBindings> createState() => _SessionBindingsState();
}

class _SessionBindingsState extends State<_SessionBindings> {
  String? _boundUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == _boundUserId) return;
    _boundUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsProvider>().startForUser(userId);
      context.read<SettingsProvider>().loadForUser(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id;
    if (userId != _boundUserId) {
      _boundUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<NotificationsProvider>().startForUser(userId);
        context.read<SettingsProvider>().loadForUser(userId);
      });
    }
    return widget.child;
  }
}
