import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../providers/auth_provider.dart';

/// Shows a confirmation dialog and logs the user out on confirm.
Future<void> confirmAndLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log out'),
      content: const Text('Are you sure you want to log out of Thriftline?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  await context.read<AuthProvider>().logout();

  if (!context.mounted) return;

  context.showSnackBar('You have been logged out.');
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
