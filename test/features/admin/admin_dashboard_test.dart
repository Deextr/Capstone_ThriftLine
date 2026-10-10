import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/constants/app_colors.dart';
import 'package:thriftline/core/theme/app_theme.dart';
import 'package:thriftline/features/admin/data/admin_dashboard_models.dart';
import 'package:thriftline/features/admin/data/admin_marketplace_dashboard.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/admin/domain/admin_dashboard_comparison.dart';
import 'package:thriftline/features/admin/domain/admin_dashboard_period.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_dashboard_widgets.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_review_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminDashboardSnapshot', () {
    test('parses aggregated dashboard JSON without fake defaults', () {
      final snapshot = AdminDashboardSnapshot.fromJson({
        'generated_at': '2026-09-28T08:00:00Z',
        'range_days': 7,
        'active_window_minutes': 15,
        'counts': {
          'total_users': 120,
          'period_users': 42,
          'period_active': 3,
          'active_now': 3,
          'pending_verifications': 2,
          'period_verifications': 5,
          'open_reports': 1,
          'period_reports': 2,
          'period_orders': 5,
          'open_disputes': 4,
          'gross_marketplace_sales': 15000,
          'platform_revenue': 300,
        },
        'sales_revenue_series': [
          {'day': '2026-09-28', 'gross': 15000, 'platform_revenue': 300},
        ],
        'registrations': [
          {'day': '2026-09-27', 'count': 2},
          {'day': '2026-09-28', 'count': 1},
        ],
        'orders_by_day': [
          {'day': '2026-09-28', 'count': 5},
        ],
        'orders_by_status': [
          {'status': 'paid', 'count': 4},
          {'status': 'cancelled', 'count': 1},
        ],
        'reports_by_day': [
          {'day': '2026-09-28', 'count': 1},
        ],
        'reports_by_status': [
          {'status': 'under_review', 'count': 1},
        ],
        'pending_verifications': [
          {
            'id': 'ver-1',
            'applicant_name': 'Maria Santos',
            'shop_name': 'Second Street',
            'submitted_at': '2026-09-27T10:00:00Z',
            'status': 'pending',
          },
        ],
        'recent_reports': [
          {
            'id': 'rep-1',
            'reporter_name': 'Alex',
            'reported_name': 'Jordan',
            'reported_role': 'seller',
            'category': 'scam_or_fraud',
            'order_number': 'TL-10482',
            'created_at': '2026-09-28T07:00:00Z',
            'status': 'under_review',
          },
          {
            'id': 'rep-2',
            'reporter_name': 'Sam',
            'reported_name': 'Riley',
            'reported_role': 'buyer',
            'category': 'harassment',
            'created_at': '2026-09-26T07:00:00Z',
            'status': 'dismissed',
          },
        ],
        'recent_orders': [
          {
            'order_number': 'TL-10482',
            'status': 'paid',
            'total_amount': 1250,
            'created_at': '2026-09-28T06:00:00Z',
          },
        ],
      });

      expect(snapshot.counts.registeredInPeriod, 42);
      expect(snapshot.counts.activeInPeriod, 3);
      expect(snapshot.counts.activeNow, 3);
      expect(snapshot.counts.pendingVerifications, 2);
      expect(snapshot.counts.verificationsSubmitted, 5);
      expect(snapshot.counts.openReports, 1);
      expect(snapshot.counts.reportsSubmitted, 2);
      expect(snapshot.counts.ordersPlaced, 5);
      expect(snapshot.counts.openDisputes, 4);
      expect(snapshot.registrationTotal, 3);
      expect(snapshot.orderTotal, 5);
      expect(snapshot.pendingVerifications.single.shopName, 'Second Street');
      expect(snapshot.recentReports.first.orderNumber, 'TL-10482');
      expect(snapshot.recentOrders.single.amountLabel, contains('1,250'));
    });

    test('filters recent reports without dropping the source list', () {
      final reports = [
        AdminDashboardReport.fromJson({
          'id': 'open',
          'reporter_name': 'Alex',
          'reported_name': 'Jordan',
          'category': 'other',
          'created_at': '2026-09-28T07:00:00Z',
          'status': kAdminReportOpenStatus,
        }),
        AdminDashboardReport.fromJson({
          'id': 'closed',
          'reporter_name': 'Sam',
          'reported_name': 'Riley',
          'category': 'other',
          'created_at': '2026-09-26T07:00:00Z',
          'status': 'resolved',
        }),
      ];

      expect(
        filterDashboardReports(
          reports,
          AdminDashboardReportFilter.underReview,
        ).map((item) => item.id),
        ['open'],
      );
      expect(
        filterDashboardReports(
          reports,
          AdminDashboardReportFilter.reviewed,
        ).map((item) => item.id),
        ['closed'],
      );
      expect(
        filterDashboardReports(reports, AdminDashboardReportFilter.all).length,
        2,
      );
    });

    test(
      'date windows cover calendar days without overlapping the next day',
      () {
        final now = DateTime(2026, 9, 28, 16, 2);
        final today = AdminDateWindow.today(now);
        expect(today.from, DateTime(2026, 9, 28));
        expect(today.toExclusive, DateTime(2026, 9, 29));

        final week = AdminDateWindow.last7Days(now);
        expect(week.from, DateTime(2026, 9, 22));
        expect(week.toExclusive, DateTime(2026, 9, 29));

        final rolling30 = AdminDateWindow.last30Days(now);
        expect(rolling30.from, DateTime(2026, 8, 30));
        expect(rolling30.toExclusive, DateTime(2026, 9, 29));

        final year = AdminDateWindow.lastYear(now);
        expect(year.from, DateTime(2025, 1, 1));
        expect(year.toExclusive, DateTime(2026, 1, 1));

        final custom = AdminDateWindow.custom(
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 10),
        );
        expect(custom.from, DateTime(2026, 9, 1));
        expect(custom.toExclusive, DateTime(2026, 9, 11));
      },
    );

    test('maps report list filters to existing database statuses', () {
      expect(adminReportListFilterStatuses(AdminReportListFilter.all), isNull);
      expect(adminReportListFilterStatuses(AdminReportListFilter.underReview), [
        kAdminReportOpenStatus,
      ]);
      expect(adminReportListFilterStatuses(AdminReportListFilter.resolved), [
        'resolved',
      ]);
      expect(
        adminReportListFilterStatuses(AdminReportListFilter.needsMoreEvidence),
        ['needs_more_evidence'],
      );
      expect(adminReportListFilterStatuses(AdminReportListFilter.dismissed), [
        'dismissed',
      ]);
    });

    test('treats socket failures as offline', () {
      expect(
        isAdminDashboardOfflineError(Exception('SocketException: failed host')),
        isTrue,
      );
      expect(isAdminDashboardOfflineError(Exception('row not found')), isFalse);
    });
  });

  group('dashboard layout', () {
    Future<void> pump(
      WidgetTester tester, {
      required Size size,
      required Widget child,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    for (final size in const [Size(320, 640), Size(800, 1024)]) {
      testWidgets('overview cards fit ${size.width.toInt()}px', (tester) async {
        final wide = size.width >= 600;
        await pump(
          tester,
          size: size,
          child: wide
              ? const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AdminOverviewCard(
                        label: 'Registered users',
                        value: 1280,
                        detail: 'All ThriftLine accounts',
                        icon: Icons.people_outline,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: AdminOverviewCard(
                        label: 'Active users',
                        value: 12,
                        detail: 'Last seen in the selected period',
                        icon: Icons.person_search_outlined,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: AdminOverviewCard(
                        label: 'Seller verifications',
                        value: 4,
                        detail: 'Waiting for review',
                        icon: Icons.storefront_outlined,
                        attention: true,
                        onTap: _noop,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: AdminOverviewCard(
                        label: 'Open reports',
                        value: 2,
                        detail: 'Waiting for review',
                        icon: Icons.flag_outlined,
                        attention: true,
                        onTap: _noop,
                      ),
                    ),
                  ],
                )
              : const Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AdminOverviewCard(
                            label: 'Registered users',
                            value: 1280,
                            detail: 'All ThriftLine accounts',
                            icon: Icons.people_outline,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: AdminOverviewCard(
                            label: 'Active users',
                            value: 12,
                            detail: 'Last seen in the selected period',
                            icon: Icons.person_search_outlined,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AdminOverviewCard(
                            label: 'Seller verifications',
                            value: 4,
                            detail: 'Waiting for review',
                            icon: Icons.storefront_outlined,
                            attention: true,
                            onTap: _noop,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: AdminOverviewCard(
                            label: 'Open reports',
                            value: 2,
                            detail: 'Waiting for review',
                            icon: Icons.flag_outlined,
                            attention: true,
                            onTap: _noop,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
        expect(find.text('Registered users'), findsOneWidget);
        expect(find.text('1,280'), findsOneWidget);
        expect(find.text('Last seen in the selected period'), findsOneWidget);
      });

      testWidgets(
        'pending verification cards stay compact at ${size.width.toInt()}px',
        (tester) async {
          await pump(
            tester,
            size: size,
            child: AdminPendingVerificationCard(
              shopName: 'Second Street',
              applicantName: 'Maria Santos',
              submittedAt: DateTime(2026, 9, 27),
              onReview: _noop,
            ),
          );
          expect(find.text('Second Street'), findsOneWidget);
          expect(find.text('Maria Santos'), findsOneWidget);
          expect(find.text('Pending'), findsOneWidget);
        },
      );

      testWidgets('filled chart stays readable at ${size.width.toInt()}px', (
        tester,
      ) async {
        await pump(
          tester,
          size: size,
          child: AdminTrendChart(
            title: 'Orders placed',
            points: [
              AdminDashboardPoint(day: DateTime(2026, 9, 22), count: 1),
              AdminDashboardPoint(day: DateTime(2026, 9, 23), count: 4),
              AdminDashboardPoint(day: DateTime(2026, 9, 24), count: 2),
            ],
            emptyMessage: 'No orders in this period.',
            breakdown: const [
              AdminDashboardStatusCount(status: 'paid', count: 5),
              AdminDashboardStatusCount(status: 'cancelled', count: 2),
            ],
            breakdownLabel: (status) => status,
          ),
        );
        expect(find.text('Orders placed'), findsOneWidget);
        expect(find.text('7 in this period'), findsOneWidget);
      });
    }

    testWidgets('report cards stay compact at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AdminReportCard(
                reportId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
                kindLabel: 'Order',
                reporterName: 'Alex Cruz',
                reporterRole: 'Buyer',
                reportedName: 'Jordan Shop',
                reportedRole: 'Seller',
                reason: 'Item not as described',
                preview: 'The jacket arrived stained and the size is wrong.',
                status: kAdminReportOpenStatus,
                statusLabel: 'Under Review',
                createdAt: DateTime(2026, 9, 28),
                orderNumber: 'TL-10482',
                onView: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Item not as described'), findsOneWidget);
      expect(find.text('View report'), findsOneWidget);
      expect(find.text('#A1B2C3D4'), findsOneWidget);
      expect(find.text('Order'), findsWidgets);
      expect(find.textContaining('Alex Cruz'), findsOneWidget);
      expect(find.text('Sep 28, 2026'), findsOneWidget);
    });
  });

  group('Admin dashboard periods', () {
    final now = DateTime.utc(2026, 10, 10, 7, 30);

    test('today is the default window and compares the same elapsed time', () {
      final today = AdminDashboardPeriod.today(now);
      expect(today.range, AdminDashboardRange.today);
      expect(today.bucket, AdminDashboardBucket.hour);
      expect(today.comparisonLabel, 'vs yesterday');
      expect(today.from, DateTime.utc(2026, 10, 9, 16));
      expect(today.toExclusive, now);
      expect(today.compareFrom, DateTime.utc(2026, 10, 8, 16));
      expect(today.compareTo, DateTime.utc(2026, 10, 9, 7, 30));
    });

    test(
      'weekly starts on Monday and yearly stays inside the previous year',
      () {
        final week = AdminDashboardPeriod.weekly(now);
        final monday = manilaWallClock(week.from!);
        expect(
          DateTime.utc(monday.year, monday.month, monday.day).weekday,
          DateTime.monday,
        );
        expect(week.comparisonLabel, 'vs previous week');
        expect(week.bucket, AdminDashboardBucket.day);

        final year = AdminDashboardPeriod.yearly(now);
        expect(year.from, DateTime.utc(2025, 12, 31, 16));
        expect(year.compareFrom, DateTime.utc(2024, 12, 31, 16));
        expect(year.compareTo!.isBefore(year.from!), isTrue);
        expect(year.bucket, AdminDashboardBucket.month);
      },
    );

    test('all time and custom ranges do not invent a comparison', () {
      final all = AdminDashboardPeriod.allTime(now);
      expect(all.from, isNull);
      expect(all.requestsComparison, isFalse);
      expect(all.bucket, AdminDashboardBucket.auto);

      final custom = AdminDashboardPeriod.custom(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 3),
        utcNow: now,
      );
      expect(custom.requestsComparison, isFalse);
      expect(custom.bucket, AdminDashboardBucket.day);
      expect(custom.toExclusive, DateTime.utc(2026, 10, 3, 16));
    });

    test('monthly comparison is clamped to the previous month', () {
      final lateMarch = DateTime.utc(2026, 3, 31, 10);
      final month = AdminDashboardPeriod.monthly(lateMarch);
      expect(month.compareTo, month.from);
    });
  });

  group('Admin period comparisons', () {
    test('shows absolute and percent change against yesterday', () {
      final delta = formatAdminPeriodDelta(
        current: 23,
        previous: 15,
        comparisonAvailable: true,
        comparisonLabel: 'vs yesterday',
        higherIsBetter: true,
        unit: 'user',
      );
      expect(delta?.text, '+8 users (+53.3%) vs yesterday');
      expect(delta?.tone, AdminDeltaTone.positive);
    });

    test('hides a percentage when the previous value is zero', () {
      final delta = formatAdminPeriodDelta(
        current: 5,
        previous: 0,
        comparisonAvailable: true,
        comparisonLabel: 'vs yesterday',
        higherIsBetter: true,
        unit: 'user',
      );
      expect(delta?.text, '+5 users vs yesterday');
      expect(delta!.text.contains('%'), isFalse);
    });

    test('hides the comparison when history is unavailable', () {
      expect(
        formatAdminPeriodDelta(
          current: 5,
          previous: null,
          comparisonAvailable: false,
          comparisonLabel: 'vs yesterday',
          higherIsBetter: true,
          unit: 'user',
        ),
        isNull,
      );
      expect(
        formatAdminPeriodDelta(
          current: 5,
          previous: 0,
          comparisonAvailable: false,
          comparisonLabel: 'vs yesterday',
          higherIsBetter: true,
        ),
        isNull,
      );
    });

    test('treats an increase in backlog as negative', () {
      final delta = formatAdminPeriodDelta(
        current: 4,
        previous: 1,
        comparisonAvailable: true,
        comparisonLabel: 'vs yesterday',
        higherIsBetter: false,
        unit: 'dispute',
      );
      expect(delta?.tone, AdminDeltaTone.negative);
    });
  });

  group('Admin marketplace snapshot', () {
    test('keeps a missing comparison null and a real zero as zero', () {
      final snapshot = AdminMarketplaceSnapshot.fromJson({
        'generated_at': '2026-10-10T07:30:00Z',
        'bucket': 'hour',
        'comparison_available': true,
        'kpis': {
          'new_users': 5,
          'new_users_previous': null,
          'completed_orders': 2,
          'completed_orders_previous': 0,
          'platform_revenue': 50.5,
          'platform_revenue_previous': 0,
          'paid_orders': 3,
          'paid_orders_previous': 1,
        },
        'activity': {
          'new_listings': 4,
          'seller_applications': 1,
          'paid_auction_orders': 1,
          'orders_awaiting_fulfillment': 6,
        },
        'attention': {
          'pending_verifications': 2,
          'open_community_disputes': 1,
          'open_order_disputes': 3,
          'open_looking_for_disputes': 0,
          'active_bidding_restrictions': 1,
          'payment_reviews': 1,
        },
        'revenue_series': [
          {'at': '2026-10-10T00:00:00Z', 'current': 50.5, 'previous': 0},
        ],
        'recent_activity': [
          {
            'kind': 'verification_submitted',
            'occurred_at': '2026-10-10T01:00:00Z',
            'title': 'Seller verification submitted',
            'detail': 'Second Street',
            'actor': 'member',
            'target_type': 'verification',
            'target_id': 'ver-1',
          },
        ],
      });

      expect(snapshot.comparisonAvailable, isTrue);
      expect(snapshot.kpis.newUsersPrevious, isNull);
      expect(snapshot.kpis.completedOrdersPrevious, 0);
      expect(snapshot.kpis.platformRevenue, 50.5);
      expect(snapshot.attention.openDisputes, 4);
      expect(snapshot.recentActivity.single.detail, 'Second Street');
      expect(snapshot.hasRevenue, isTrue);
    });

    test('rejects a payload that omits metrics', () {
      expect(
        () => AdminMarketplaceSnapshot.fromJson({'success': true}),
        throwsFormatException,
      );
    });
  });

  testWidgets('dashboard filter defaults and empty revenue state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              AdminDashboardPeriodBar(
                period: AdminDashboardPeriod.today(
                  DateTime.utc(2026, 10, 10, 7, 30),
                ),
                onSelected: (_) async {},
              ),
              const AdminKpiTile(
                label: 'New users',
                value: '23',
                caption: 'Registered in this period',
                delta: AdminPeriodDelta(
                  text: '+8 users (+53.3%) vs yesterday',
                  tone: AdminDeltaTone.positive,
                ),
              ),
              const AdminRevenueChart(
                points: [],
                bucket: AdminDashboardBucket.hour,
                showComparison: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('+8 users (+53.3%) vs yesterday'), findsOneWidget);
    expect(find.text('No platform revenue in this period.'), findsOneWidget);

    final delta = tester.widget<Text>(
      find.text('+8 users (+53.3%) vs yesterday'),
    );
    expect(delta.style?.color, AppColors.success);
  });
}

void _noop() {}
