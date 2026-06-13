import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/app/app.dart';
import 'package:thriftline/core/routes/app_router.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/features/auth/data/auth_service.dart';
import 'package:thriftline/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:thriftline/providers/app_provider.dart';
import 'package:thriftline/providers/auth_provider.dart';
import 'package:thriftline/providers/data_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Thriftline app renders splash screen', (tester) async {
    final prefs = await SharedPreferencesService.init();
    final authProvider = AuthProvider(prefs, AuthService());
    final appProvider = AppProvider(prefs);
    final dataProvider = DataProvider();
    await authProvider.init();

    final router = createAppRouter(
      authProvider: authProvider,
      appProvider: appProvider,
    );

    await tester.pumpWidget(
      ThriftlineApp(
        prefs: prefs,
        router: router,
        authProvider: authProvider,
        appProvider: appProvider,
        dataProvider: dataProvider,
      ),
    );
    await tester.pump();

    expect(find.text('Thriftline'), findsOneWidget);
    expect(find.text('AI-powered thrift marketplace'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  group('AuthService', () {
    late AuthService authService;

    setUp(() {
      authService = AuthService();
    });

    test('authenticates buyer credentials', () {
      final result = authService.authenticate('maya_buys', 'buyer123');
      expect(result.success, isTrue);
      expect(result.user?.isBuyer, isTrue);
    });

    test('authenticates seller credentials', () {
      final result = authService.authenticate('vintagevibes_ph', 'seller123');
      expect(result.success, isTrue);
      expect(result.user?.isSeller, isTrue);
    });

    test('rejects invalid credentials', () {
      final result = authService.authenticate('maya_buys', 'wrong');
      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
    });
  });

  group('Onboarding', () {
    testWidgets('shows three onboarding pages with indicators', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      final appProvider = AppProvider(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppProvider>.value(
            value: appProvider,
            child: const OnboardingScreen(),
          ),
        ),
      );

      expect(find.text('Discover Hidden Gems'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Bid & Win'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Sell Your Thrifts'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    test('completeOnboarding persists first launch flag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      final appProvider = AppProvider(prefs);

      expect(appProvider.isFirstLaunch, isTrue);

      await appProvider.completeOnboarding();

      expect(appProvider.isFirstLaunch, isFalse);
      expect(prefs.isOnboardingComplete, isTrue);
    });
  });

  group('AuthProvider', () {
    test('restores session from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'buyer',
        'username': 'maya_buys',
        'user_id': 'buyer_maya',
        'display_name': 'Maya Santos',
      });

      final prefs = await SharedPreferencesService.init();
      final authProvider = AuthProvider(prefs, AuthService());
      await authProvider.init();

      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isBuyer, isTrue);
      expect(authProvider.username, 'maya_buys');
    });

    test('logout clears session', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'seller',
        'username': 'thrift_trendy',
        'user_id': 'seller_rico',
        'display_name': 'Thrift & Trendy',
      });

      final prefs = await SharedPreferencesService.init();
      final authProvider = AuthProvider(prefs, AuthService());
      await authProvider.init();
      await authProvider.logout();

      expect(authProvider.isAuthenticated, isFalse);
      expect(prefs.isLoggedIn, isFalse);
      expect(prefs.username, isNull);
    });
  });
}
