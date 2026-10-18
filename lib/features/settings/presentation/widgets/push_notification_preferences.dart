import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/account_mode.dart';
import '../../../../widgets/thrift_widgets.dart' show showThriftSnackBar;
import '../../domain/push_notification_status_copy.dart';

class PushNotificationPreferences extends StatefulWidget {
  const PushNotificationPreferences({super.key, required this.mode});

  final AccountMode mode;

  @override
  State<PushNotificationPreferences> createState() =>
      _PushNotificationPreferencesState();
}

class _PushNotificationPreferencesState
    extends State<PushNotificationPreferences> {
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
    final reg = await push.diagnostics(
      appPushEnabled: settings.pushFor(widget.mode),
    );
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
    if (!mounted) return;
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
    if (!mounted) return;
    await _refreshStatus();
  }

  Future<void> _retryRegistration() async {
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final ok = await push.syncRegistrationForUser(auth.user?.id);
    if (!mounted) return;
    await _refreshStatus();
    if (!mounted) return;
    final failureMessage = userFacingPushRegisterError(push.lastRegisterError);
    showThriftSnackBar(
      context,
      ok
          ? 'This device is set up for push alerts.'
          : failureMessage.isNotEmpty
              ? failureMessage
              : 'Could not set up push alerts on this device.',
      isError: !ok,
    );
  }

  Future<void> _requestOsPermission() async {
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final granted = await push.requestOsPermission(showRationale: true);
    if (!mounted) return;
    await _refreshStatus();
    if (!mounted) return;
    if (granted && context.read<SettingsProvider>().pushFor(widget.mode)) {
      await push.syncRegistrationForUser(auth.user?.id);
      if (!mounted) return;
      await _refreshStatus();
    }
    if (!granted && mounted) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          title: Text('Push notifications', style: AppTypography.body),
          subtitle: Text(
            widget.mode == AccountMode.seller
                ? 'Order and shop alerts on this device'
                : 'Bids, orders, and messages on this device',
            style: AppTypography.caption,
          ),
          value: appEnabled,
          activeThumbColor: AppColors.primary,
          onChanged: settings.isSavingPush ? null : _onAppToggle,
        ),
        if (appEnabled) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (_loadingPermission)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Checking alert setup…'),
                ],
              ),
            )
          else if (reg != null)
            _PushDeliveryStatus(
              registration: reg,
              permission: perm,
              onAllowNotifications: _requestOsPermission,
              onOpenDeviceSettings: push.openOsAppSettings,
              onRetryRegistration: _retryRegistration,
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'In-app notifications always appear in your Notifications tab. '
            'Push alerts follow the toggle above and your phone’s notification settings.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textHint,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _PushDeliveryStatus extends StatelessWidget {
  const _PushDeliveryStatus({
    required this.registration,
    required this.permission,
    required this.onAllowNotifications,
    required this.onOpenDeviceSettings,
    required this.onRetryRegistration,
  });

  final PushRegistrationDiagnostics registration;
  final NotificationPermissionSnapshot? permission;
  final VoidCallback onAllowNotifications;
  final VoidCallback onOpenDeviceSettings;
  final VoidCallback onRetryRegistration;

  @override
  Widget build(BuildContext context) {
    final title = pushDeliveryStatusTitle(registration);
    final message = pushRegistrationStatusMessage(registration);
    final perm = permission;
    final needsOsPermission =
        perm != null && !perm.unavailable && !perm.osGranted;
    final needsRegistrationRetry =
        registration.appPushEnabled &&
        registration.osPermissionGranted &&
        !registration.readyForPush &&
        registration.firebaseInitialized;

    final (IconData icon, Color iconColor) = switch (true) {
      _ when registration.readyForPush => (
        Icons.check_circle_rounded,
        AppColors.success,
      ),
      _ when needsOsPermission => (
        Icons.notifications_off_outlined,
        AppColors.warning,
      ),
      _ => (Icons.info_outline_rounded, AppColors.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: AppTypography.caption.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (needsOsPermission) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: perm.canRequestAgain
                    ? onAllowNotifications
                    : onOpenDeviceSettings,
                child: Text(
                  perm.canRequestAgain
                      ? 'Allow notifications'
                      : 'Open phone settings',
                ),
              ),
            ),
          ] else if (needsRegistrationRetry) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetryRegistration,
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
