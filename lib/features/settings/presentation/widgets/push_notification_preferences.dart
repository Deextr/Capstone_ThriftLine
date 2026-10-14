import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/account_mode.dart';
import '../../../../widgets/thrift_widgets.dart' show showThriftSnackBar;

class PushNotificationPreferences extends StatefulWidget {
  const PushNotificationPreferences({super.key, required this.mode});

  final AccountMode mode;

  @override
  State<PushNotificationPreferences> createState() =>
      _PushNotificationPreferencesState();
}

class _PushNotificationPreferencesState extends State<PushNotificationPreferences> {
  NotificationPermissionSnapshot? _permission;
  PushRegistrationDiagnostics? _registration;
  bool _loadingPermission = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final push = context.read<PushNotificationService>();
    final settings = context.read<SettingsProvider>();
    final snap = await push.permissionSnapshot();
    final reg = await push.diagnostics(appPushEnabled: settings.pushFor(widget.mode));
    if (!mounted) return;
    setState(() {
      _permission = snap;
      _registration = reg;
      _loadingPermission = false;
    });
  }

  Future<void> _onAppToggle(bool value) async {
    final settings = context.read<SettingsProvider>();
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final ok = await settings.setPushNotifications(value, mode: widget.mode);
    if (!context.mounted) return;
    if (!ok) {
      showThriftSnackBar(
        context,
        'Could not save push notification preference.',
        isError: true,
      );
      return;
    }
    if (value) {
      await push.syncRegistrationForUser(auth.user?.id);
    } else {
      await push.revokeCurrentDeviceToken();
    }
    await _refreshStatus();
  }

  Future<void> _retryRegistration() async {
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final ok = await push.syncRegistrationForUser(auth.user?.id);
    await _refreshStatus();
    if (!context.mounted) return;
    showThriftSnackBar(
      context,
      ok
          ? 'This device is registered for push alerts.'
          : push.lastRegisterError ?? 'Could not register this device.',
      isError: !ok,
    );
  }

  Future<void> _requestOsPermission() async {
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final granted = await push.requestOsPermission(showRationale: true);
    await _refreshStatus();
    if (!context.mounted) return;
    if (granted && context.read<SettingsProvider>().pushFor(widget.mode)) {
      await push.syncRegistrationForUser(auth.user?.id);
      await _refreshStatus();
    }
    if (!granted) {
      showThriftSnackBar(
        context,
        'Notifications are off in your device settings. Enable them there to receive alerts.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final push = context.read<PushNotificationService>();
    final appEnabled = settings.pushFor(widget.mode);
    final perm = _permission;
    final reg = _registration;

    return Column(
      children: [
        SwitchListTile(
          title: Text('Push notifications', style: AppTypography.body),
          subtitle: Text(
            widget.mode == AccountMode.seller
                ? 'Seller workspace alerts on this device'
                : 'Buyer workspace alerts on this device',
            style: AppTypography.caption,
          ),
          value: appEnabled,
          activeThumbColor: AppColors.primary,
          onChanged: settings.isSavingPush ? null : _onAppToggle,
        ),
        if (_loadingPermission)
          const ListTile(
            dense: true,
            title: Text('Checking device permission…'),
          )
        else if (perm != null && !perm.unavailable) ...[
          ListTile(
            dense: true,
            title: Text(
              'Device permission',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              perm.osGranted
                  ? 'Allowed — ThriftLine can show alerts on this device.'
                  : 'Not allowed — the app cannot show system alerts until you enable them.',
              style: AppTypography.caption,
            ),
            trailing: perm.osGranted
                ? Icon(Icons.check_circle, color: AppColors.success, size: 20)
                : Icon(Icons.notifications_off_outlined, color: AppColors.warning),
          ),
          if (!perm.osGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: perm.canRequestAgain
                      ? _requestOsPermission
                      : () => push.openOsAppSettings(),
                  child: Text(
                    perm.canRequestAgain
                        ? 'Allow notifications'
                        : 'Open device settings',
                  ),
                ),
              ),
            ),
        ],
        if (reg != null) ...[
          ListTile(
            dense: true,
            title: Text(
              'Push setup on this device',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _registrationSummary(reg),
              style: AppTypography.caption.copyWith(height: 1.35),
            ),
          ),
          if (!reg.readyForPush)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _retryRegistration,
                  child: const Text('Register this device again'),
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'In-app notifications always appear in the Notifications screen. '
            'Push alerts respect this toggle and your device permission.',
            style: AppTypography.caption.copyWith(color: AppColors.textHint),
          ),
        ),
      ],
    );
  }

  String _registrationSummary(PushRegistrationDiagnostics reg) {
    if (!reg.firebaseConfigured) {
      return 'Firebase is not configured. Add FIREBASE_* keys to .env and restart the app.';
    }
    if (!reg.firebaseInitialized) {
      return 'Firebase failed to start. Check .env values and google-services.json.';
    }
    if (!reg.appPushEnabled) {
      return 'Push is off for this workspace. Turn on the toggle above.';
    }
    if (!reg.osPermissionGranted) {
      return 'Waiting for device notification permission.';
    }
    if (reg.hasDeviceToken) {
      final suffix = reg.tokenSuffix;
      return suffix == null
          ? 'Device registered for push.'
          : 'Device registered (token …$suffix).';
    }
    return reg.lastError ?? 'Not registered yet. Tap Register this device again.';
  }
}
