import 'package:flutter/material.dart';

import 'app/admin_app.dart';
import 'core/config/admin_dotenv.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/admin_app_router.dart';
import 'core/services/shared_preferences_service.dart';
import 'core/services/supabase_service.dart';
import 'features/admin/data/admin_portal_data_access.dart';
import 'features/admin/data/admin_portal_session.dart';
import 'features/auth/data/auth_service.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await loadAdminDotEnv();
    await SupabaseConfig.initialize();

    final prefs = await SharedPreferencesService.init();
    final supabaseService = SupabaseService();
    AdminPortalDataAccess.bind(supabaseService);
    final authService = AuthService(supabaseService);
    final authProvider = AuthProvider(prefs, authService);
    final themeProvider = ThemeProvider(prefs);
    AdminPortalSession.refresh = authProvider.reloadUser;

    await authProvider.init();

    final router = createAdminAppRouter(authProvider: authProvider);

    runApp(
      ThriftlineAdminApp(
        prefs: prefs,
        router: router,
        authProvider: authProvider,
        themeProvider: themeProvider,
        supabaseService: supabaseService,
      ),
    );
  } catch (error, stack) {
    debugPrint('Admin portal failed to start: $error\n$stack');
    runApp(_AdminStartupErrorApp(message: error.toString()));
  }
}

class _AdminStartupErrorApp extends StatelessWidget {
  const _AdminStartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThriftLine Admin',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'ThriftLine Admin could not start.\n\n$message',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
