import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void sellerTrustBadgeWidgetTests() {
  qaGroup('SellerTrustBadge', () {
    qaWidgetTest('shows label and numeric score from the score', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SellerTrustBadge(
            trustScore: 92,
            isVerified: false,
            shopName: 'Ukay Haven',
          ),
        ),
      );

      expect(find.text('Highly Trusted Seller (92/100)'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
    });

    qaWidgetTest('hides the number when showNumericScore is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SellerTrustBadge(
            trustScore: 50,
            isVerified: false,
            shopName: 'Ukay Haven',
            showNumericScore: false,
          ),
        ),
      );

      expect(find.text('Under Review'), findsOneWidget);
      expect(find.textContaining('/100'), findsNothing);
    });

    qaWidgetTest('stored trust level overrides the score bucket', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SellerTrustBadge(
            trustScore: 10,
            isVerified: false,
            shopName: 'Ukay Haven',
            trustLevel: 'Trusted Seller',
          ),
        ),
      );

      expect(find.text('Trusted Seller (10/100)'), findsOneWidget);
    });

    qaWidgetTest('tapping opens the trust explanation sheet', (tester) async {
      await tester.pumpWidget(
        _host(
          const SellerTrustBadge(
            trustScore: 92,
            isVerified: true,
            shopName: 'Ukay Haven',
          ),
        ),
      );

      await tester.tap(find.byType(SellerTrustBadge));
      await tester.pumpAndSettle();

      expect(find.text('Trust & Verification'), findsOneWidget);
      expect(find.text('Ukay Haven'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('92/100'), findsOneWidget);
    });
  });
}
