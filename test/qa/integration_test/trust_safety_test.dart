import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/models/community_report_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/return_shipment.dart';
import 'package:thriftline/models/review_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Leave Review harness simulating the post-delivery review flow.
class _LeaveReviewHarness extends StatefulWidget {
  const _LeaveReviewHarness({
    required this.orderId,
    required this.sellerName,
    required this.onSubmit,
  });

  final String orderId;
  final String sellerName;
  final void Function(int rating, String comment) onSubmit;

  @override
  State<_LeaveReviewHarness> createState() => _LeaveReviewHarnessState();
}

class _LeaveReviewHarnessState extends State<_LeaveReviewHarness> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);

    if (_selectedRating == 0) {
      setState(() => _error = 'Please select a star rating.');
      return;
    }

    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      setState(() => _error = 'Please write a review comment.');
      return;
    }

    widget.onSubmit(_selectedRating, comment);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave a Review')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate your experience with ${widget.sellerName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  key: Key('review-star-$starIndex'),
                  icon: Icon(
                    starIndex <= _selectedRating
                        ? Icons.star
                        : Icons.star_border,
                    color: starIndex <= _selectedRating
                        ? const Color(0xFFF59E0B)
                        : Colors.grey,
                    size: 36,
                  ),
                  onPressed: () =>
                      setState(() => _selectedRating = starIndex),
                );
              }),
            ),
            const SizedBox(height: 16),
            ThriftTextField(
              key: const Key('review-comment-input'),
              label: 'Your Review',
              controller: _commentController,
              maxLines: 4,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('review-error'),
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
            ThriftButton(
              key: const Key('review-submit-button'),
              label: 'Submit Review',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Report User harness simulating the community reporting flow.
class _ReportUserHarness extends StatefulWidget {
  const _ReportUserHarness({
    required this.reportedUsername,
    required this.categories,
    required this.onSubmit,
  });

  final String reportedUsername;
  final List<String> categories;
  final void Function(String category, String details) onSubmit;

  @override
  State<_ReportUserHarness> createState() => _ReportUserHarnessState();
}

class _ReportUserHarnessState extends State<_ReportUserHarness> {
  String? _selectedCategory;
  final _detailsController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);

    if (_selectedCategory == null) {
      setState(() => _error = 'Please select a report category.');
      return;
    }

    final details = _detailsController.text.trim();
    if (details.length < 20) {
      setState(() => _error = 'Please provide at least 20 characters of detail.');
      return;
    }

    widget.onSubmit(_selectedCategory!, details);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report @${widget.reportedUsername}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Why are you reporting this user?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final category in widget.categories)
              RadioListTile<String>(
                key: Key('report-cat-$category'),
                title: Text(category),
                value: category,
                groupValue: _selectedCategory,
                onChanged: (v) => setState(() => _selectedCategory = v),
              ),
            const SizedBox(height: 12),
            ThriftTextField(
              key: const Key('report-details-input'),
              label: 'Details',
              controller: _detailsController,
              maxLines: 4,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('report-error'),
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
            ThriftButton(
              key: const Key('report-submit-button'),
              label: 'Submit Report',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

Finder _fieldInput(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(TextFormField),
    );

void trustSafetyIntegrationTests() {
  qaGroup('Trust & Safety Integration Flow', () {
    qaIntegrationTest(
        'buyer leaves review with star rating and comment validation', (
      tester,
    ) async {
      int? submittedRating;
      String? submittedComment;

      await tester.pumpWidget(
        MaterialApp(
          home: _LeaveReviewHarness(
            orderId: 'order-rev-001',
            sellerName: 'Ukay Thrift Shop',
            onSubmit: (rating, comment) {
              submittedRating = rating;
              submittedComment = comment;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Rate your experience with Ukay Thrift Shop'),
        findsOneWidget,
      );

      // 1. Try submitting without rating
      await tester.ensureVisible(find.byKey(const Key('review-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please select a star rating.'), findsOneWidget);
      expect(submittedRating, isNull);

      // 2. Select 4-star rating
      await tester.tap(find.byKey(const Key('review-star-4')));
      await tester.pumpAndSettle();

      // 3. Try submitting without comment
      await tester.tap(find.byKey(const Key('review-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please write a review comment.'), findsOneWidget);

      // 4. Enter comment and submit
      await tester.enterText(
        _fieldInput('review-comment-input'),
        'Great item! Fast shipping and exactly as described.',
      );

      await tester.ensureVisible(find.byKey(const Key('review-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-submit-button')));
      await tester.pumpAndSettle();

      expect(submittedRating, 4);
      expect(submittedComment,
          'Great item! Fast shipping and exactly as described.');
    });

    qaIntegrationTest(
        'user reports another user with category and minimum detail', (
      tester,
    ) async {
      final categories = [
        'Counterfeit item',
        'Harassment',
        'Fraud/Scam',
        'Other',
      ];

      String? submittedCategory;
      String? submittedDetails;

      await tester.pumpWidget(
        MaterialApp(
          home: _ReportUserHarness(
            reportedUsername: 'scam_seller_99',
            categories: categories,
            onSubmit: (category, details) {
              submittedCategory = category;
              submittedDetails = details;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report @scam_seller_99'), findsOneWidget);

      // 1. Submit without category
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please select a report category.'), findsOneWidget);

      // 2. Select category
      await tester.tap(find.byKey(const Key('report-cat-Fraud/Scam')));
      await tester.pumpAndSettle();

      // 3. Submit with too-short details
      await tester.enterText(
        _fieldInput('report-details-input'),
        'They scammed me.',
      );
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Please provide at least 20 characters of detail.'),
        findsOneWidget,
      );
      expect(submittedCategory, isNull);

      // 4. Provide adequate details
      await tester.enterText(
        _fieldInput('report-details-input'),
        'This seller sent a fake item and refused to respond to messages.',
      );
      await tester.ensureVisible(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit-button')));
      await tester.pumpAndSettle();

      expect(submittedCategory, 'Fraud/Scam');
      expect(submittedDetails,
          'This seller sent a fake item and refused to respond to messages.');
    });

    qaIntegrationTest(
        'ReviewModel.fromSupabase parses rating, reviewer, and photos', (
      tester,
    ) async {
      final review = ReviewModel.fromSupabase({
        'review_id': 'rev-001',
        'order_id': 'order-001',
        'reviewer_id': 'buyer-qa-1',
        'reviewed_user_id': 'seller-1',
        'rating': 5,
        'review_text': 'Amazing vintage find! Would buy again.',
        'review_type': 'buyer_to_seller',
        'created_at': '2026-10-04T14:00:00.000Z',
        'reviewer': {
          'username': 'dexter_r',
          'full_name': 'Dexter Ramos',
          'avatar': 'https://example.com/avatar.jpg',
        },
        'review_photos': [
          {
            'review_photo_id': 'photo-1',
            'file_path': 'reviews/rev-001/photo1.jpg',
          },
          {
            'review_photo_id': 'photo-2',
            'file_path': 'reviews/rev-001/photo2.jpg',
          },
          // Empty file_path should be filtered out
          {
            'review_photo_id': 'photo-3',
            'file_path': '',
          },
        ],
      });

      expect(review.id, 'rev-001');
      expect(review.rating, 5);
      expect(review.comment, 'Amazing vintage find! Would buy again.');
      expect(review.reviewType, 'buyer_to_seller');
      expect(review.reviewerName, 'Dexter Ramos');
      expect(review.reviewerUsername, 'dexter_r');
      expect(review.photos.length, 2); // empty file_path filtered
      expect(review.photos.first.filePath, 'reviews/rev-001/photo1.jpg');

      // Equality by ID
      final sameReview = ReviewModel.fromSupabase({
        'review_id': 'rev-001',
        'order_id': 'order-001',
        'reviewer_id': 'buyer-qa-1',
        'reviewed_user_id': 'seller-1',
        'rating': 3,
        'review_text': 'Different text same ID',
        'created_at': '2026-10-04T15:00:00.000Z',
      });
      expect(review == sameReview, isTrue);
    });

    qaIntegrationTest(
        'CommunityReportModel lifecycle from filing to admin resolution', (
      tester,
    ) async {
      final report = CommunityReportModel.fromSupabase(
        {
          'report_id': 'rpt-001',
          'reporter_id': 'buyer-qa-1',
          'reported_user_id': 'seller-scam-1',
          'category': 'fraud',
          'details': 'Seller sent counterfeit product.',
          'status': 'under_review',
          'created_at': '2026-10-04T14:00:00.000Z',
          'order_id': 'order-001',
        },
        reportedUser: {
          'username': 'scam_seller',
          'full_name': 'Scam Seller',
          'role': 'seller',
          'shop_name': 'Fake Shop',
        },
        reporterUser: {
          'username': 'dexter_r',
          'full_name': 'Dexter Ramos',
          'role': 'buyer',
        },
        orderNumber: 'TL-8001',
        orderTitle: 'Vintage Denim Jacket',
      );

      expect(report.id, 'rpt-001');
      expect(report.reportedUsername, 'scam_seller');
      expect(report.reportedDisplayName, 'Scam Seller');
      expect(report.reporterUsername, 'dexter_r');
      expect(report.reportedRole, 'seller');
      expect(report.reportedShopName, 'Fake Shop');
      expect(report.category, 'fraud');
      expect(report.status, 'under_review');
      expect(report.orderNumber, 'TL-8001');
      expect(report.orderTitle, 'Vintage Denim Jacket');
      expect(report.adminResponse, isNull);
      expect(report.resolvedAt, isNull);

      // Admin resolves the report
      final resolved = report.copyWith(
        status: 'resolved',
        adminResponse: 'Seller account suspended. Refund issued.',
        resolvedAt: DateTime.now(),
        reviewedBy: 'admin-001',
      );

      expect(resolved.status, 'resolved');
      expect(resolved.adminResponse,
          'Seller account suspended. Refund issued.');
      expect(resolved.resolvedAt, isNotNull);
      expect(resolved.reviewedBy, 'admin-001');
      expect(resolved.id, report.id); // Same report
    });

    qaIntegrationTest(
        'return shipment status labels and progress index are correct', (
      tester,
    ) async {
      // Status labels
      expect(returnStatusLabel('not_required'), 'No return needed');
      expect(returnStatusLabel('waiting_for_rider'), 'Waiting for rider');
      expect(returnStatusLabel('rider_assigned'), 'Rider assigned');
      expect(returnStatusLabel('picked_up'), 'Picked up');
      expect(returnStatusLabel('returned'), 'Returned');
      expect(returnStatusLabel('cancelled_by_admin'), 'Return stopped');
      expect(returnStatusLabel('unknown'), 'Return update');

      // Status hints
      expect(
        returnStatusHint('waiting_for_rider'),
        'The seller is responsible for arranging a rider.',
      );
      expect(
        returnStatusHint('rider_assigned'),
        'Hand the item to the rider when they arrive.',
      );

      // Progress indices
      expect(returnProgressIndex('waiting_for_rider'), 1);
      expect(returnProgressIndex('rider_assigned'), 2);
      expect(returnProgressIndex('picked_up'), 3);
      expect(returnProgressIndex('returned'), 4);
      expect(returnProgressIndex('not_required'), 0);

      // Progress steps count
      expect(kReturnProgressSteps.length, 5);

      // Return shipment state flags
      final openReturn = ReturnShipment.fromSupabase({
        'return_id': 'ret-001',
        'dispute_id': 'disp-001',
        'order_id': 'order-001',
        'return_required': true,
        'status': 'waiting_for_rider',
      });

      expect(openReturn.isOpen, isTrue);
      expect(openReturn.needsRider, isTrue);
      expect(openReturn.canHandOff, isFalse);
      expect(openReturn.canConfirmReceived, isFalse);

      final assignedReturn = ReturnShipment.fromSupabase({
        'return_id': 'ret-001',
        'dispute_id': 'disp-001',
        'order_id': 'order-001',
        'return_required': true,
        'status': 'rider_assigned',
        'rider_name': 'Rider Juan',
        'rider_phone': '09181234567',
      });

      expect(assignedReturn.canHandOff, isTrue);
      expect(assignedReturn.needsRider, isTrue);

      final pickedUp = ReturnShipment.fromSupabase({
        'return_id': 'ret-001',
        'dispute_id': 'disp-001',
        'order_id': 'order-001',
        'return_required': true,
        'status': 'picked_up',
      });

      expect(pickedUp.canConfirmReceived, isTrue);
      expect(pickedUp.isOpen, isTrue);

      final completed = ReturnShipment.fromSupabase({
        'return_id': 'ret-001',
        'dispute_id': 'disp-001',
        'order_id': 'order-001',
        'return_required': true,
        'status': 'returned',
      });

      expect(completed.isOpen, isFalse);
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    trustSafetyIntegrationTests();
  });
}
