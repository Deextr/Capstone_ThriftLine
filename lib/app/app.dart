import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/shared_preferences_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_service.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';

class ThriftlineApp extends StatelessWidget {
  const ThriftlineApp({
    super.key,
    required this.prefs,
    required this.router,
    required this.authProvider,
    required this.appProvider,
    required this.dataProvider,
  });

  final SharedPreferencesService prefs;
  final GoRouter router;
  final AuthProvider authProvider;
  final AppProvider appProvider;
  final DataProvider dataProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferencesService>.value(value: prefs),
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ChangeNotifierProvider<DataProvider>.value(value: dataProvider),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    );
  }
}
