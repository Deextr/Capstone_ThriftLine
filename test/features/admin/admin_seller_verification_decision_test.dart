import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/theme/app_theme.dart';
import 'package:thriftline/features/admin/data/admin_verification_service.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_review_widgets.dart';

SellerApplication _pendingApplication() {
  return SellerApplication(
    id: '11111111-1111-4111-8111-111111111111',
    userId: '22222222-2222-4222-8222-222222222222',
    shopName: 'Second Street Thrift',
    shopAddress: '123 Sample St',
    barangay: 'Buhangin',
    city: 'Davao City',
    status: 'pending',
    submittedAt: DateTime.utc(2026, 10, 10),
    livenessPassed: true,
    livenessResult: const {'face': true},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPanel(
    WidgetTester tester, {
    required Size size,
    required Widget panel,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: size.width, child: panel),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('decision actions stay content-sized in desktop sidebar', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      size: const Size(400, 720),
      panel: SellerVerificationDecisionPanel(
        application: _pendingApplication(),
        busy: false,
        onApprove: () {},
        onReject: () {},
      ),
    );

    expect(find.text('Approve seller'), findsOneWidget);
    expect(find.text('Reject application'), findsOneWidget);

    final rejectControl = find.ancestor(
      of: find.text('Reject application'),
      matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton,
      ),
    );
    final approveControl = find.ancestor(
      of: find.text('Approve seller'),
      matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton,
      ),
    );
    expect(rejectControl, findsOneWidget);
    expect(approveControl, findsOneWidget);

    final rejectBox = tester.getRect(rejectControl);
    final approveBox = tester.getRect(approveControl);
    expect(rejectBox.left, lessThan(approveBox.left));
  });

  testWidgets('completed decision shows rejection reason', (tester) async {
    final app = SellerApplication(
      id: '11111111-1111-4111-8111-111111111111',
      userId: '22222222-2222-4222-8222-222222222222',
      shopName: 'Second Street Thrift',
      shopAddress: '123 Sample St',
      barangay: 'Buhangin',
      city: 'Davao City',
      status: 'rejected',
      submittedAt: DateTime.utc(2026, 10, 10),
      livenessPassed: false,
      livenessResult: const {},
      rejectionReason: 'ID photo was blurry.',
    );

    await pumpPanel(
      tester,
      size: const Size(320, 720),
      panel: SellerVerificationDecisionPanel(
        application: app,
        busy: false,
        onApprove: () {},
        onReject: () {},
      ),
    );

    expect(find.text('This application was rejected'), findsOneWidget);
    expect(find.text('ID photo was blurry.'), findsOneWidget);
    expect(find.text('Approve seller'), findsNothing);
  });
}
