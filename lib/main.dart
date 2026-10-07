import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/routes/deep_link_dispatch.dart';
import 'core/routes/password_recovery_coordinator.dart';
import 'core/routes/paymongo_return_coordinator.dart';
import 'core/services/shared_preferences_service.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/data/auth_service.dart';
import 'features/buyer/data/paymongo_pending_checkout_store.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/data_provider.dart';
import 'providers/following_shops_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/saved_items_provider.dart';
import 'providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables (.env file).
  await dotenv.load(fileName: '.env');

  // Initialize Supabase SDK.
  await SupabaseConfig.initialize(
    detectSessionInUriPredicate: isSupabaseAuthDeepLink,
  );

  final prefs = await SharedPreferencesService.init();
  final supabaseService = SupabaseService();
  final authService = AuthService(supabaseService);
  final authProvider = AuthProvider(prefs, authService);
  final appProvider = AppProvider(prefs);
  final dataProvider = DataProvider();
  final notificationsProvider = NotificationsProvider(supabaseService);
  final settingsProvider = SettingsProvider(supabaseService);
  final savedItemsProvider = SavedItemsProvider(supabaseService, authProvider);
  final followingShopsProvider = FollowingShopsProvider(supabaseService);
  final cartProvider = CartProvider(supabaseService);

  await authProvider.init();

  final paymongoReturn = PaymongoReturnCoordinator(
    pendingStore: PaymongoPendingCheckoutStore(prefs),
  );
  await paymongoReturn.restorePersistedCheckout();
  final passwordRecovery = PasswordRecoveryCoordinator(
    onRecoveryLinkAccepted: authProvider.markPasswordRecoveryPending,
    onRecoveryLinkFailed: authProvider.abandonPasswordRecoveryLinkAttempt,
  );
  await attachAppDeepLinks(
    paymongoReturn: paymongoReturn,
    passwordRecovery: passwordRecovery,
  );

  final router = createMobileAppRouter(
    authProvider: authProvider,
    appProvider: appProvider,
    paymongoReturn: paymongoReturn,
    passwordRecovery: passwordRecovery,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PasswordRecoveryCoordinator>.value(
          value: passwordRecovery,
        ),
        ChangeNotifierProvider<PaymongoReturnCoordinator>.value(
          value: paymongoReturn,
        ),
      ],
      child: ThriftlineApp(
        prefs: prefs,
        router: router,
        authProvider: authProvider,
        appProvider: appProvider,
        dataProvider: dataProvider,
        notificationsProvider: notificationsProvider,
        settingsProvider: settingsProvider,
        savedItemsProvider: savedItemsProvider,
        followingShopsProvider: followingShopsProvider,
        cartProvider: cartProvider,
        supabaseService: supabaseService,
      ),
    ),
  );
}
