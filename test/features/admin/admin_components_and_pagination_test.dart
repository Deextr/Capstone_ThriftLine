import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/constants/app_colors.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_ui_components.dart';

void main() {
  group('AdminPagination Widget Tests', () {
    testWidgets('renders item count range correctly for first page', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPagination(
              currentPage: 0,
              totalItems: 87,
              pageSize: 10,
              onPageChanged: (_) {},
              onPageSizeChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Showing 1–10 of 87 results'), findsOneWidget);
      expect(find.text('Rows per page:'), findsOneWidget);
    });

    testWidgets(
      'renders item count range correctly for last page with partial count',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminPagination(
                currentPage: 8,
                totalItems: 87,
                pageSize: 10,
                onPageChanged: (_) {},
              ),
            ),
          ),
        );

        expect(find.text('Showing 81–87 of 87 results'), findsOneWidget);
      },
    );

    testWidgets('handles 0 items gracefully', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPagination(
              currentPage: 0,
              totalItems: 0,
              pageSize: 10,
              onPageChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Showing 0 results'), findsOneWidget);
    });

    testWidgets(
      'disables previous button on first page and triggers next button callback',
      (tester) async {
        int? changedPage;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminPagination(
                currentPage: 0,
                totalItems: 30,
                pageSize: 10,
                onPageChanged: (page) => changedPage = page,
              ),
            ),
          ),
        );

        // Find icon buttons for navigation
        final chevronLeft = find.byIcon(Icons.chevron_left);
        final chevronRight = find.byIcon(Icons.chevron_right);
        expect(chevronLeft, findsOneWidget);
        expect(chevronRight, findsOneWidget);

        // Tap next page
        await tester.tap(chevronRight);
        await tester.pumpAndSettle();
        expect(changedPage, 1);
      },
    );

    testWidgets(
      'renders condensed page numbers with ellipsis when page count > 7',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminPagination(
                currentPage: 5,
                totalItems: 120, // 12 pages
                pageSize: 10,
                onPageChanged: (_) {},
              ),
            ),
          ),
        );

        // Page 1 should always be visible
        expect(find.text('1'), findsOneWidget);
        // Page 12 should always be visible
        expect(find.text('12'), findsOneWidget);
        // Current page 6 (0-indexed 5) should be visible
        expect(find.text('6'), findsOneWidget);
        // Ellipsis should be present
        expect(find.text('…'), findsWidgets);
      },
    );
  });

  group('AdminStatusBadge Tests', () {
    testWidgets('renders pending status with warning colors and label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdminStatusBadge(status: 'pending')),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders approved status with success color and label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdminStatusBadge(status: 'approved')),
        ),
      );

      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('renders rejected status with error color and label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdminStatusBadge(status: 'rejected')),
        ),
      );

      expect(find.text('Rejected'), findsOneWidget);
    });
  });

  group('AdminSearchField Tests', () {
    testWidgets('accepts text and triggers callbacks', (tester) async {
      String? submittedQuery;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminSearchField(
              hintText: 'Search applicants...',
              controller: controller,
              onSubmitted: (q) => submittedQuery = q,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Dexter');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(submittedQuery, 'Dexter');
    });
  });

  group('AdminStatCard Tests', () {
    testWidgets('renders label, count, and triggers onTap callback', (
      tester,
    ) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminStatCard(
              label: 'Pending Review',
              count: 14,
              icon: Icons.pending_actions,
              accentColor: AppColors.warning,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);

      await tester.tap(find.text('Pending Review'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
