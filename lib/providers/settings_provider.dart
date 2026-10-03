import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';
import '../features/auth/domain/account_mode.dart';

class UserSettings {
  const UserSettings({
    required this.buyerPushEnabled,
    required this.sellerPushEnabled,
    required this.buyerEmailEnabled,
    required this.sellerEmailEnabled,
  });

  final bool buyerPushEnabled;
  final bool sellerPushEnabled;
  final bool buyerEmailEnabled;
  final bool sellerEmailEnabled;

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        buyerPushEnabled:
            json['buyer_push_notifications_enabled'] as bool? ??
            json['push_notifications_enabled'] as bool? ??
            true,
        sellerPushEnabled:
            json['seller_push_notifications_enabled'] as bool? ??
            json['push_notifications_enabled'] as bool? ??
            true,
        buyerEmailEnabled:
            json['buyer_email_notifications_enabled'] as bool? ??
            json['email_notifications_enabled'] as bool? ??
            false,
        sellerEmailEnabled:
            json['seller_email_notifications_enabled'] as bool? ??
            json['email_notifications_enabled'] as bool? ??
            false,
      );

  static const defaults = UserSettings(
    buyerPushEnabled: true,
    sellerPushEnabled: true,
    buyerEmailEnabled: false,
    sellerEmailEnabled: false,
  );

  bool pushFor(AccountMode mode) => switch (mode) {
        AccountMode.buyer => buyerPushEnabled,
        AccountMode.seller => sellerPushEnabled,
      };

  bool emailFor(AccountMode mode) => switch (mode) {
        AccountMode.buyer => buyerEmailEnabled,
        AccountMode.seller => sellerEmailEnabled,
      };

  UserSettings copyWith({
    bool? buyerPushEnabled,
    bool? sellerPushEnabled,
    bool? buyerEmailEnabled,
    bool? sellerEmailEnabled,
  }) {
    return UserSettings(
      buyerPushEnabled: buyerPushEnabled ?? this.buyerPushEnabled,
      sellerPushEnabled: sellerPushEnabled ?? this.sellerPushEnabled,
      buyerEmailEnabled: buyerEmailEnabled ?? this.buyerEmailEnabled,
      sellerEmailEnabled: sellerEmailEnabled ?? this.sellerEmailEnabled,
    );
  }
}

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._supabase);
  final SupabaseService _supabase;
  UserSettings _settings = UserSettings.defaults;
  String? _userId;
  bool _savingPush = false;
  bool _savingEmail = false;

  UserSettings get settings => _settings;
  bool get isSavingPush => _savingPush;
  bool get isSavingEmail => _savingEmail;

  bool pushFor(AccountMode mode) => _settings.pushFor(mode);
  bool emailFor(AccountMode mode) => _settings.emailFor(mode);

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
      _settings =
          row != null ? UserSettings.fromJson(row) : UserSettings.defaults;
    } catch (e) {
      debugPrint('SettingsProvider.loadForUser error: $e');
    }
    notifyListeners();
  }

  Future<bool> setPushNotifications(bool value, {required AccountMode mode}) {
    return _updateModeSetting(
      mode: mode,
      push: value,
      savingFlag: (v) => _savingPush = v,
    );
  }

  Future<bool> setEmailNotifications(bool value, {required AccountMode mode}) {
    return _updateModeSetting(
      mode: mode,
      email: value,
      savingFlag: (v) => _savingEmail = v,
    );
  }

  Future<bool> _updateModeSetting({
    required AccountMode mode,
    bool? push,
    bool? email,
    required void Function(bool) savingFlag,
  }) async {
    final previous = _settings;
    _settings = _settings.copyWith(
      buyerPushEnabled: mode == AccountMode.buyer && push != null
          ? push
          : null,
      sellerPushEnabled: mode == AccountMode.seller && push != null
          ? push
          : null,
      buyerEmailEnabled: mode == AccountMode.buyer && email != null
          ? email
          : null,
      sellerEmailEnabled: mode == AccountMode.seller && email != null
          ? email
          : null,
    );
    notifyListeners();

    final patch = <String, dynamic>{};
    if (mode == AccountMode.buyer && push != null) {
      patch['buyer_push_notifications_enabled'] = push;
      patch['push_notifications_enabled'] = push;
    }
    if (mode == AccountMode.seller && push != null) {
      patch['seller_push_notifications_enabled'] = push;
    }
    if (mode == AccountMode.buyer && email != null) {
      patch['buyer_email_notifications_enabled'] = email;
      patch['email_notifications_enabled'] = email;
    }
    if (mode == AccountMode.seller && email != null) {
      patch['seller_email_notifications_enabled'] = email;
    }

    savingFlag(true);
    notifyListeners();
    final ok = await _persist(patch);
    savingFlag(false);
    if (!ok) {
      _settings = previous;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> _persist(Map<String, dynamic> patch) async {
    final userId = _userId;
    if (userId == null) return false;
    try {
      await _supabase.client.from('user_settings').upsert({
        'user_id': userId,
        ...patch,
      });
      return true;
    } catch (e) {
      debugPrint('SettingsProvider.persist error: $e');
      return false;
    }
  }
}
