import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../auth/domain/trusted_device.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../controllers/admin_portal_session_controller.dart';

Future<void> confirmAdminSignOut(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final emailPassword = showEmailTrustedDeviceLogout(
    usesEmailPasswordAuth: auth.usesEmailPasswordAuth,
  );

  final choice = await showDialog<LogoutChoice>(
    context: context,
    barrierDismissible: !auth.isLoading,
    builder: (_) => _AdminSignOutDialog(showTrustedDeviceOptions: emailPassword),
  );

  if (choice == null || choice == LogoutChoice.cancel || !context.mounted) {
    return;
  }

  final session = context.read<AdminPortalSessionController>();
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final forgetDevice = choice == LogoutChoice.forgetDevice;
  messenger?.clearSnackBars();

  BuildContext? progressDialogContext;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        progressDialogContext = dialogContext;
        return const _AdminSignOutProgressDialog();
      },
    ),
  );

  String? error;
  session.beginManualSignOut();
  try {
    await session.revokeServerSession(reason: 'sign_out');
    error = await auth.logout(forgetDevice: forgetDevice);
    if (error == null) {
      await session.publishSignedOutToOtherTabs();
    }
  } finally {
    session.endManualSignOut();
    final dialogContext = progressDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      final dialogRoute = ModalRoute.of(dialogContext);
      if (dialogRoute != null && dialogRoute.isCurrent) {
        Navigator.of(dialogContext).pop();
      }
    }
    messenger?.clearSnackBars();
  }

  if (error != null) {
    if (context.mounted) {
      context.showSnackBar(error, isError: true);
    }
    return;
  }

  router.go(RouteNames.adminLogin);
}

class _AdminSignOutDialog extends StatelessWidget {
  const _AdminSignOutDialog({required this.showTrustedDeviceOptions});

  final bool showTrustedDeviceOptions;

  void _pick(BuildContext context, LogoutChoice choice) {
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sign out',
                      style: AppTypography.subheading.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => _pick(context, LogoutChoice.cancel),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, color: palette.textHint, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (showTrustedDeviceOptions) ...[
                _SignOutPrimaryAction(
                  label: 'Log out',
                  onPressed: () => _pick(context, LogoutChoice.logout),
                ),
                const SizedBox(height: 10),
                _SignOutSecondaryAction(
                  label: 'Log out and forget this device',
                  onPressed: () => _pick(context, LogoutChoice.forgetDevice),
                ),
              ] else
                _SignOutPrimaryAction(
                  label: 'Log out',
                  onPressed: () => _pick(context, LogoutChoice.logout),
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _pick(context, LogoutChoice.cancel),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignOutPrimaryAction extends StatefulWidget {
  const _SignOutPrimaryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<_SignOutPrimaryAction> createState() => _SignOutPrimaryActionState();
}

class _SignOutPrimaryActionState extends State<_SignOutPrimaryAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: AppGradients.fill(
          gradient: AppGradients.buttonGradient,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          boxShadow: _hovered ? AppGradients.emphasisShadow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutSecondaryAction extends StatefulWidget {
  const _SignOutSecondaryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<_SignOutSecondaryAction> createState() =>
      _SignOutSecondaryActionState();
}

class _SignOutSecondaryActionState extends State<_SignOutSecondaryAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = palette.errorForeground;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: _hovered ? palette.errorSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          border: Border.all(
            color: _hovered ? color.withValues(alpha: 0.5) : palette.border,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            hoverColor: Colors.transparent,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminSignOutProgressDialog extends StatelessWidget {
  const _AdminSignOutProgressDialog();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppPalette.brandPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Signing out…',
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
