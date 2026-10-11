import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/admin/controllers/admin_users_controller.dart';
import 'package:thriftline/features/admin/data/admin_users_service.dart';
import 'package:thriftline/features/admin/presentation/web/admin_web_users_page.dart';

class _Directory extends AdminUsersService {
  _Directory() : super(SupabaseService());

  int disableCalls = 0;
  String? lastReason;

  static final buyer = MarketplaceUserRow(
    userId: 'buyer-1',
    fullName: 'Maya Cruz',
    email: 'maya@example.com',
    username: 'maya',
    role: 'buyer',
    accountStatus: 'active',
    accountType: 'buyer',
    createdAt: DateTime.utc(2026, 1, 2),
    sellerApproved: false,
    canDisable: true,
  );

  static final seller = MarketplaceUserRow(
    userId: 'seller-1',
    fullName: 'Leo Santos',
    email: 'leo@example.com',
    username: 'leo',
    role: 'seller',
    accountStatus: 'banned',
    accountType: 'buyer_seller',
    createdAt: DateTime.utc(2026, 2, 3),
    sellerApproved: true,
    shopName: 'Leo Studio',
    verificationStatus: 'approved',
    canDisable: false,
    sanctionReason: 'Repeated confirmed Looking For violations',
  );

  @override
  Future<MarketplaceUsersPage> list({
    required int page,
    required int pageSize,
    String? search,
    String? accountType,
    String? status,
  }) async {
    return MarketplaceUsersPage(
      rows: [buyer, seller],
      total: 2,
      counts: const MarketplaceUserCounts(
        total: 21,
        active: 21,
        disabled: 0,
        banned: 0,
      ),
    );
  }

  @override
  Future<MarketplaceUserRow?> detail(String userId) async {
    if (userId == seller.userId) return seller;
    return buyer;
  }

  @override
  Future<MarketplaceDisableResult> disable({
    required String userId,
    required String reason,
    required String notes,
  }) async {
    disableCalls += 1;
    lastReason = reason;
    return const MarketplaceDisableResult(ok: true);
  }
}

Future<AdminUsersController> _pump(
  WidgetTester tester,
  _Directory directory,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = AdminUsersController(
    supabase: SupabaseService(),
    service: directory,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AdminUsersController>.value(
      value: controller,
      child: const MaterialApp(home: Scaffold(body: AdminWebUsersPage())),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets(
    'shows marketplace users and keeps disable off a banned account',
    (tester) async {
      final directory = _Directory();
      await _pump(tester, directory);

      expect(find.text('Maya Cruz'), findsOneWidget);
      expect(find.text('maya@example.com'), findsOneWidget);
      expect(find.text('Buyer'), findsWidgets);
      expect(find.text('Buyer & Seller'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Banned'), findsWidgets);
      expect(find.text('Disable account'), findsOneWidget);
      expect(find.text('Disable unavailable'), findsOneWidget);
      expect(find.text('View details'), findsNothing);
    },
  );

  testWidgets('cancel leaves the account unchanged', (tester) async {
    final directory = _Directory();
    await _pump(tester, directory);

    await tester.tap(find.text('Disable account'));
    await tester.pumpAndSettle();

    expect(find.text('Maya Cruz'), findsWidgets);
    expect(
      find.textContaining('This is a disable, not a permanent ban.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(directory.disableCalls, 0);
    expect(find.text('Account disabled.'), findsNothing);
  });

  testWidgets('row tap opens user details for a banned account', (
    tester,
  ) async {
    final directory = _Directory();
    await _pump(tester, directory);

    await tester.tap(find.text('Leo Santos').first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Leo Santos'), findsWidgets);
    expect(
      find.text('Account banned. This account is already restricted.'),
      findsOneWidget,
    );
    expect(
      find.text('Repeated confirmed Looking For violations'),
      findsOneWidget,
    );
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('narrow width still shows the account and its actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = _Directory();
    final controller = AdminUsersController(
      supabase: SupabaseService(),
      service: directory,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AdminUsersController>.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: AdminWebUsersPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('leo@example.com'), findsOneWidget);
    expect(find.text('Disable account'), findsOneWidget);
    expect(find.text('Disable unavailable'), findsOneWidget);
  });
}
