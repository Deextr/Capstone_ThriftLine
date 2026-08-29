import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../auth/domain/legal_documents.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            SwitchListTile(
              title: const Text('Push Notifications'),
              value: settings.pushNotificationsEnabled,
              onChanged: (value) =>
                  context.read<SettingsProvider>().setPushNotifications(value),
            ),
            SwitchListTile(
              title: const Text('Email Notifications'),
              value: settings.emailNotificationsEnabled,
              onChanged: (value) =>
                  context.read<SettingsProvider>().setEmailNotifications(value),
            ),
            ListTile(
              title: const Text('Language'),
              subtitle: const Text('English'),
              trailing: const Icon(Icons.chevron_right),
            ),
            ListTile(
              title: const Text('Phone number'),
              subtitle: Text(
                user?.isPhoneVerified == true
                    ? (user?.phone ?? 'Verified')
                    : 'Not verified',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(RouteNames.verifyPhone),
            ),
            ListTile(
              title: const Text('Addresses'),
              subtitle: const Text('Delivery addresses for checkout'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(RouteNames.addresses),
            ),
            ListTile(
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push(RouteNames.legalDocument(LegalDocumentType.privacy)),
            ),
            ListTile(
              title: const Text('Terms and Conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push(RouteNames.legalDocument(LegalDocumentType.terms)),
            ),
          ],
        ),
      ),
    );
  }
}
