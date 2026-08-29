import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';

class UserSettings {
  const UserSettings({
    required this.pushNotificationsEnabled,
    required this.emailNotificationsEnabled,
    required this.language,
  });

  final bool pushNotificationsEnabled;
  final bool emailNotificationsEnabled;
  final String language;

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        pushNotificationsEnabled: json['push_notifications_enabled'] as bool? ?? true,
        emailNotificationsEnabled: json['email_notifications_enabled'] as bool? ?? false,
        language: json['language'] as String? ?? 'en',
      );

  static const defaults = UserSettings(
    pushNotificationsEnabled: true,
    emailNotificationsEnabled: false,
    language: 'en',
  );
}

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._supabase);
  final SupabaseService _supabase;
  UserSettings _settings = UserSettings.defaults;
  String? _userId;

  UserSettings get settings => _settings;
  bool get pushNotificationsEnabled => _settings.pushNotificationsEnabled;

  Future<void> loadForUser(String? userId) async {
    _userId = userId;
    if (userId == null) {
      _settings = UserSettings.defaults;
      notifyListeners();
      return;
    }
    try {
      final row = await _supabase.client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      _settings = row != null ? UserSettings.fromJson(row) : UserSettings.defaults;
    } catch (e) {
      debugPrint('SettingsProvider.loadForUser error: $e');
    }
    notifyListeners();
  }

  Future<void> setPushNotifications(bool value) async {
    _settings = UserSettings(
      pushNotificationsEnabled: value,
      emailNotificationsEnabled: _settings.emailNotificationsEnabled,
      language: _settings.language,
    );
    notifyListeners();
    await _persist({'push_notifications_enabled': value});
  }

  Future<void> setEmailNotifications(bool value) async {
    _settings = UserSettings(
      pushNotificationsEnabled: _settings.pushNotificationsEnabled,
      emailNotificationsEnabled: value,
      language: _settings.language,
    );
    notifyListeners();
    await _persist({'email_notifications_enabled': value});
  }

  Future<void> _persist(Map<String, dynamic> patch) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await _supabase.client.from('user_settings').update(patch).eq('user_id', userId);
    } catch (e) {
      debugPrint('SettingsProvider.persist error: $e');
    }
  }
}
