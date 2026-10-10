import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/services/shared_preferences_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_palette_lerp_sync.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_service.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class ThriftlineAdminApp extends StatelessWidget {
  const ThriftlineAdminApp({
    super.key,
    required this.prefs,
    required this.router,
    required this.authProvider,
    required this.themeProvider,
    required this.supabaseService,
  });

  final SharedPreferencesService prefs;
  final GoRouter router;
  final AuthProvider authProvider;
  final ThemeProvider themeProvider;
  final SupabaseService supabaseService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferencesService>.value(value: prefs),
        Provider<SupabaseService>.value(value: supabaseService),
        Provider<AuthService>(create: (_) => AuthService(supabaseService)),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp.router(
            title: 'ThriftLine Admin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.themeMode,
            themeAnimationDuration: const Duration(milliseconds: 320),
            themeAnimationCurve: Curves.easeInOutCubic,
            routerConfig: router,
            builder: (context, child) {
              return AppPaletteLerpSync(
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
