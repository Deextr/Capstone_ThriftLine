import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/firebase_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/shared_preferences_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/account_mode.dart';

/// One-time, non-blocking prompt to enable OS notification permission.
class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({super.key, required this.mode});

  final AccountMode mode;

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> {
  bool _visible = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  Future<void> _evaluate() async {
    if (!FirebaseConfig.isConfigured) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final prefs = context.read<SharedPreferencesService>();
    if (prefs.pushPermissionPromptDismissed(widget.mode.name)) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final settings = context.read<SettingsProvider>();
    if (!settings.pushFor(widget.mode)) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final snap = await context.read<PushNotificationService>().permissionSnapshot();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _visible = !snap.unavailable && !snap.osGranted && snap.canRequestAgain;
    });
  }

  Future<void> _dismiss() async {
    await context.read<SharedPreferencesService>().setPushPermissionPromptDismissed(
      widget.mode.name,
      true,
    );
    if (mounted) setState(() => _visible = false);
  }

  Future<void> _allow() async {
    final push = context.read<PushNotificationService>();
    final auth = context.read<AuthProvider>();
    final granted = await push.requestOsPermission(showRationale: true);
    await context.read<SharedPreferencesService>().setPushPermissionPromptDismissed(
      widget.mode.name,
      true,
    );
    if (granted) {
      await push.syncRegistrationForUser(auth.user?.id);
    }
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || !_visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay updated on orders and messages',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Turn on notifications to get shipping updates, bids, and chat replies even when the app is closed.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: _dismiss, child: const Text('Not now')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _allow,
                    child: const Text('Allow notifications'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
