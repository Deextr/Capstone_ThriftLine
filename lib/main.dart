import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/services/shared_preferences_service.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/data/auth_service.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables (.env file).
  await dotenv.load(fileName: '.env');

  // Initialize Supabase SDK.
  await SupabaseConfig.initialize();

  final prefs = await SharedPreferencesService.init();
  final supabaseService = SupabaseService();
  final authService = AuthService(supabaseService);
  final authProvider = AuthProvider(prefs, authService);
  final appProvider = AppProvider(prefs);
  final dataProvider = DataProvider();

  await authProvider.init();

  final router = createAppRouter(
    authProvider: authProvider,
    appProvider: appProvider,
  );

  runApp(
    ThriftlineApp(
      prefs: prefs,
      router: router,
      authProvider: authProvider,
      appProvider: appProvider,
      dataProvider: dataProvider,
      supabaseService: supabaseService,
    ),
  );
}
