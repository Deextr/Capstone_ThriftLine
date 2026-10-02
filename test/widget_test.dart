import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppProvider', () {
    test('skips intro carousel on first launch', () async {
      final prefs = await SharedPreferencesService.init();
      final appProvider = AppProvider(prefs);

      expect(appProvider.isOnboardingComplete, isTrue);
      expect(appProvider.isFirstLaunch, isFalse);
    });

    test('completeOnboarding persists flag when called', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      final appProvider = AppProvider(prefs);

      await appProvider.completeOnboarding();

      expect(prefs.isOnboardingComplete, isTrue);
    });
  });
}
