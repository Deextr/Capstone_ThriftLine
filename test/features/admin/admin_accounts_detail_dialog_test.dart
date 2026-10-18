import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/core/theme/app_theme.dart';
import 'package:thriftline/features/admin/controllers/admin_accounts_controller.dart';
import 'package:thriftline/features/admin/data/admin_account_models.dart';
import 'package:thriftline/features/admin/data/admin_account_service.dart';
import 'package:thriftline/features/admin/presentation/web/admin_web_accounts_page.dart';

class _FakeAdminAccountService extends AdminAccountService {
  _FakeAdminAccountService() : super(SupabaseService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account detail dialog opens without provider lookup error', (
    tester,
  ) async {
    final controller = AdminAccountsController(
      service: _FakeAdminAccountService(),
    );
    final account = AdminAccountRecord(
      userId: '11111111-1111-4111-8111-111111111111',
      fullName: 'Portal Admin',
      email: 'admin@example.com',
      role: 'admin',
      accountStatus: 'active',
      displayStatus: 'active',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showAdminAccountDetailDialog(
                  context: context,
                  account: account,
                  controller: controller,
                  onDisable: (_) async {},
                  onEnable: (_) async {},
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Disable account'), findsOneWidget);
    expect(find.text('Administrator details'), findsOneWidget);
    expect(find.text('admin@example.com'), findsWidgets);
  });
}
