import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/admin_app.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/admin_app_router.dart';
import 'core/services/shared_preferences_service.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/data/auth_service.dart';
import 'providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await SupabaseConfig.initialize();

  final prefs = await SharedPreferencesService.init();
  final supabaseService = SupabaseService();
  final authService = AuthService(supabaseService);
  final authProvider = AuthProvider(prefs, authService);

  await authProvider.init();

  final router = createAdminAppRouter(authProvider: authProvider);

  runApp(
    ThriftlineAdminApp(
      prefs: prefs,
      router: router,
      authProvider: authProvider,
      supabaseService: supabaseService,
    ),
  );
}
