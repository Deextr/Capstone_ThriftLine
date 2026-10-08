import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/features/admin/data/admin_moderation_queue_service.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/admin/presentation/web/admin_web_disputes_page.dart';
import 'package:thriftline/models/community_report_model.dart';

void main() {
  group('Admin Disputes Navigation & Categories Rules', () {
    test('AdminModerationCategory values are in the exact required order', () {
      const categories = AdminModerationCategory.values;
      expect(categories.length, 4);
      expect(categories[0], AdminModerationCategory.all);
      expect(categories[1], AdminModerationCategory.community);
      expect(categories[2], AdminModerationCategory.order);
      expect(categories[3], AdminModerationCategory.lookingFor);
    });

    test('adminModerationCategoryLabel returns the updated names', () {
      expect(
        adminModerationCategoryLabel(AdminModerationCategory.all),
        'All',
      );
      expect(
        adminModerationCategoryLabel(AdminModerationCategory.community),
        'Community Disputes',
      );
      expect(
        adminModerationCategoryLabel(AdminModerationCategory.order),
        'Order Disputes',
      );
      expect(
        adminModerationCategoryLabel(AdminModerationCategory.lookingFor),
        'Looking For Disputes',
      );
    });

    test('adminModerationCategoryParam formats correctly for backend queries', () {
      expect(adminModerationCategoryParam(AdminModerationCategory.all), 'all');
      expect(
        adminModerationCategoryParam(AdminModerationCategory.community),
        'community',
      );
      expect(
        adminModerationCategoryParam(AdminModerationCategory.order),
        'order',
      );
      expect(
        adminModerationCategoryParam(AdminModerationCategory.lookingFor),
        'looking_for',
      );
    });

    test('adminModerationCategoryFromParam parses all categories safely', () {
      expect(
        adminModerationCategoryFromParam('all'),
        AdminModerationCategory.all,
      );
      expect(
        adminModerationCategoryFromParam('community'),
        AdminModerationCategory.community,
      );
      expect(
        adminModerationCategoryFromParam('order'),
        AdminModerationCategory.order,
      );
      expect(
        adminModerationCategoryFromParam('orders'),
        AdminModerationCategory.order,
      );
      expect(
        adminModerationCategoryFromParam('looking_for'),
        AdminModerationCategory.lookingFor,
      );
      expect(
        adminModerationCategoryFromParam('looking-for'),
        AdminModerationCategory.lookingFor,
      );
      expect(adminModerationCategoryFromParam('invalid'), isNull);
      expect(adminModerationCategoryFromParam(null), isNull);
    });

    test('adminDisputesForCategory routes match expected paths', () {
      expect(
        RouteNames.adminDisputesForCategory(AdminModerationCategory.all),
        RouteNames.adminReportsAll,
      );
      expect(
        RouteNames.adminDisputesForCategory(AdminModerationCategory.community),
        RouteNames.adminReportsCommunity,
      );
      expect(
        RouteNames.adminDisputesForCategory(AdminModerationCategory.order),
        RouteNames.adminReportsOrders,
      );
      expect(
        RouteNames.adminDisputesForCategory(AdminModerationCategory.lookingFor),
        RouteNames.adminReportsLookingFor,
      );
    });

    test('adminReportsCategoryFor maps all to adminReportsAll', () {
      expect(
        RouteNames.adminReportsCategoryFor(AdminReportKind.all),
        RouteNames.adminReportsAll,
      );
      expect(
        RouteNames.adminReportsCategoryFor(AdminReportKind.community),
        RouteNames.adminReportsCommunity,
      );
      expect(
        RouteNames.adminReportsCategoryFor(AdminReportKind.order),
        RouteNames.adminReportsOrders,
      );
      expect(
        RouteNames.adminReportsCategoryFor(AdminReportKind.lookingFor),
        RouteNames.adminReportsLookingFor,
      );
    });

    test('adminModerationCaseKindShortLabel formats dispute categories cleanly', () {
      expect(
        adminModerationCaseKindShortLabel('community_report'),
        'Community',
      );
      expect(adminModerationCaseKindShortLabel('order_report'), 'Order');
      expect(
        adminModerationCaseKindShortLabel('looking_for_report'),
        'Looking For',
      );
      expect(adminModerationCaseKindShortLabel('unknown'), 'Dispute');
    });

    test('adminModerationCaseKindLabel returns dispute titles', () {
      expect(
        adminModerationCaseKindLabel('community_report'),
        'Community Dispute',
      );
      expect(adminModerationCaseKindLabel('order_report'), 'Order Dispute');
      expect(
        adminModerationCaseKindLabel('looking_for_report'),
        'Looking For Dispute',
      );
    });
  });

  group('AdminModerationCaseRow Unified Normalization', () {
    test('parses from unified JSON correctly', () {
      final json = {
        'source': 'report',
        'case_id': 'rep-101',
        'case_kind': 'community_report',
        'category': 'harassment',
        'summary': 'User was abusive in chat messages.',
        'status_raw': 'under_review',
        'actor_name': 'Alice Buyer',
        'subject_name': 'Bob Seller',
        'order_number': null,
        'created_at': '2026-10-08T08:00:00Z',
      };

      final row = AdminModerationCaseRow.fromJson(json);
      expect(row.source, 'report');
      expect(row.caseId, 'rep-101');
      expect(row.caseKind, 'community_report');
      expect(row.category, 'harassment');
      expect(row.statusRaw, 'under_review');
      expect(row.actorName, 'Alice Buyer');
      expect(row.subjectName, 'Bob Seller');
      expect(row.orderNumber, isNull);
    });

    test('normalizes community report vs order report', () {
      final communityReport = CommunityReportModel(
        id: 'c-1',
        reporterId: 'u-1',
        reportedUserId: 'u-2',
        reportedUsername: 'baduser',
        reportedDisplayName: 'Bad User',
        reporterUsername: 'gooduser',
        reporterDisplayName: 'Good User',
        category: 'harassment',
        details: 'Sent harassing messages',
        status: 'under_review',
        createdAt: DateTime.now(),
      );

      final rowComm = AdminModerationCaseRow.fromReport(communityReport);
      expect(rowComm.caseKind, 'community_report');

      final orderReport = CommunityReportModel(
        id: 'o-1',
        reporterId: 'u-1',
        reportedUserId: 'u-2',
        reportedUsername: 'seller1',
        reportedDisplayName: 'Seller One',
        reporterUsername: 'buyer1',
        reporterDisplayName: 'Buyer One',
        category: 'counterfeit_received',
        orderId: 'ord-123',
        orderNumber: 'TL-9999',
        details: 'Received fake item',
        status: 'under_review',
        createdAt: DateTime.now(),
      );

      final rowOrder = AdminModerationCaseRow.fromReport(orderReport);
      expect(rowOrder.caseKind, 'order_report');
      expect(rowOrder.orderNumber, 'TL-9999');
    });
  });

  group('Admin Report Decision Rules', () {
    test('canDecideReport returns true for under_review and needs_more_evidence', () {
      expect(canDecideReport('under_review'), isTrue);
      expect(canDecideReport('needs_more_evidence'), isTrue);
      expect(canDecideReport('resolved'), isFalse);
      expect(canDecideReport('dismissed'), isFalse);
      expect(canDecideReport('closed'), isFalse);
    });

    test('adminResponseError validates minimum length', () {
      expect(adminResponseError('Short', decision: 'resolved'), isNotNull);
      expect(
        adminResponseError(
          'This is a valid response meeting minimum requirements.',
          decision: 'resolved',
        ),
        isNull,
      );
      expect(
        adminResponseError(
          'Need more photos',
          decision: 'needs_more_evidence',
        ),
        isNotNull,
      );
      expect(
        adminResponseError(
          'Please provide clear photos of the item and courier packaging.',
          decision: 'needs_more_evidence',
        ),
        isNull,
      );
    });
  });

  group('DisputeCategorySegmentedNav Widget Tests', () {
    testWidgets('renders all 4 dispute categories in order and triggers selection', (tester) async {
      AdminModerationCategory? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DisputeCategorySegmentedNav(
              selectedCategory: AdminModerationCategory.all,
              onCategorySelected: (cat) => selected = cat,
            ),
          ),
        ),
      );

      // Verify all 4 tabs appear in UI
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Community Disputes'), findsOneWidget);
      expect(find.text('Order Disputes'), findsOneWidget);
      expect(find.text('Looking For Disputes'), findsOneWidget);

      // Tap on Community Disputes
      await tester.tap(find.text('Community Disputes'));
      await tester.pumpAndSettle();
      expect(selected, AdminModerationCategory.community);

      // Tap on Order Disputes
      await tester.tap(find.text('Order Disputes'));
      await tester.pumpAndSettle();
      expect(selected, AdminModerationCategory.order);

      // Tap on Looking For Disputes
      await tester.tap(find.text('Looking For Disputes'));
      await tester.pumpAndSettle();
      expect(selected, AdminModerationCategory.lookingFor);
    });
  });
}
