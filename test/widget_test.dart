import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:thriftline/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NOTE: AuthService and AuthProvider tests that relied on hardcoded mock
  // credentials have been removed. Auth now goes through Supabase and
  // requires integration tests with a running Supabase instance.
  // ─────────────────────────────────────────────────────────────────────────

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
}
