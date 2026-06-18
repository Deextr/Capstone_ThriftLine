import 'package:flutter/foundation.dart';

import '../core/services/shared_preferences_service.dart';

/// Manages global application state (onboarding).
class AppProvider extends ChangeNotifier {
  AppProvider(this._prefs) {
    _isOnboardingComplete = _prefs.isOnboardingComplete;
    //_isOnboardingComplete = false;
  }

  final SharedPreferencesService _prefs;

  bool _isOnboardingComplete = false;
  bool _isLoading = false;

  bool get isOnboardingComplete => _isOnboardingComplete;
  bool get isFirstLaunch => !_isOnboardingComplete;
  bool get isLoading => _isLoading;

  Future<void> completeOnboarding() async {
    _isLoading = true;
    notifyListeners();

    await _prefs.setOnboardingComplete(true);
    _isOnboardingComplete = true;

    _isLoading = false;
    notifyListeners();
  }
}
