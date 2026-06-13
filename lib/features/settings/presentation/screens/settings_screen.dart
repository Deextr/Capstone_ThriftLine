import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../widgets/thrift_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          children: [
            SwitchListTile(title: const Text('Push Notifications'), value: true, onChanged: (_) {}),
            SwitchListTile(title: const Text('Email Notifications'), value: false, onChanged: (_) {}),
            ListTile(title: const Text('Language'), subtitle: const Text('English'), trailing: const Icon(Icons.chevron_right)),
            ListTile(title: const Text('Privacy Policy'), trailing: const Icon(Icons.chevron_right), onTap: () => showThriftSnackBar(context, 'Opening privacy policy...')),
            ListTile(title: const Text('Terms of Service'), trailing: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}
