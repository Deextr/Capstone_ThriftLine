import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../providers/auth_provider.dart';
import '../../domain/trusted_device.dart';

enum LogoutChoice { cancel, logout, forgetDevice }

/// Confirms logout.
///
/// Email/password accounts see the 7-day trusted-device options.
/// Google Sign-In never uses that email code, so those accounts get a
/// simple confirmation.
Future<void> confirmAndLogout(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final emailPassword = showEmailTrustedDeviceLogout(
    usesEmailPasswordAuth: auth.usesEmailPasswordAuth,
  );
  debugPrint(
    'Logout: trustedDeviceOptions=$emailPassword '
    'identities=${auth.user?.authIdentityProviders} '
    'buyerSellerMode=${auth.activeAccount.name}',
  );

  final choice = await showDialog<LogoutChoice>(
    context: context,
    builder: (context) {
      if (!emailPassword) {
        return AlertDialog(
          title: const Text('Log out'),
          content: const Text(
            'Are you sure you want to log out of ThriftLine? '
            'You will sign in with Google again next time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(LogoutChoice.cancel),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(LogoutChoice.logout),
              child: const Text('Log out'),
            ),
          ],
        );
      }

      return AlertDialog(
        title: const Text('Log out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Logging out keeps this phone trusted until 7 days after the last '
              'email code. You still need your password next time, and the code '
              'can be skipped while that trust is valid.',
            ),
            const SizedBox(height: AppConstants.spacingLg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(LogoutChoice.logout),
              child: const Text('Log out'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(LogoutChoice.forgetDevice),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Log out and forget this device'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(LogoutChoice.cancel),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );

  if (choice == null || choice == LogoutChoice.cancel || !context.mounted) {
    return;
  }

  final error = await context.read<AuthProvider>().logout(
    forgetDevice: choice == LogoutChoice.forgetDevice,
  );

  if (!context.mounted) return;
  if (error != null) {
    context.showSnackBar(error, isError: true);
    return;
  }

  context.showSnackBar(
    choice == LogoutChoice.forgetDevice
        ? 'Logged out. This phone will ask for an email code next time.'
        : 'You have been logged out.',
  );
  context.go(RouteNames.login);
}

/// App bar action that opens the logout confirmation flow.
class LogoutIconButton extends StatelessWidget {
  const LogoutIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Log out',
      onPressed: () => confirmAndLogout(context),
    );
  }
}

/// Profile card showing the current user with a logout button.
class AuthProfileCard extends StatelessWidget {
  const AuthProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.colorScheme.primaryContainer,
                  child: Icon(
                    auth.isSeller
                        ? Icons.storefront
                        : Icons.shopping_bag_outlined,
                    color: context.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.displayName ?? 'User',
                        style: context.textTheme.titleMedium,
                      ),
                      Text(
                        '@${auth.username ?? ''}',
                        style: context.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppConstants.spacingXs),
                      Chip(
                        label: Text(
                          auth.isSeller ? 'Seller' : 'Buyer',
                          style: context.textTheme.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingLg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => confirmAndLogout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
