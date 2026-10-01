import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/delivery_report_mapping.dart';
import 'package:thriftline/features/trust_safety/data/report_reasons.dart';
import 'package:thriftline/features/trust_safety/data/review_rules.dart';
import 'package:thriftline/models/community_report_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/review_model.dart';

void main() {
  group('review rules', () {
    test('accepts only 1-5 star ratings', () {
      expect(reviewRatingError(0), isNotNull);
      expect(reviewRatingError(6), isNotNull);
      expect(reviewRatingError(999), isNotNull);
      expect(reviewRatingError(1), isNull);
      expect(reviewRatingError(5), isNull);
    });

    test('limits optional comments to 1000 characters', () {
      expect(reviewCommentError(''), isNull);
      expect(reviewCommentError('Great seller'), isNull);
      expect(reviewCommentError('a' * 1001), isNotNull);
    });

    test('allows edits only within 24 hours', () {
      final created = DateTime.utc(2026, 9, 13, 2);
      expect(
        canEditReview(created, now: created.add(const Duration(hours: 23))),
        isTrue,
      );
      expect(
        canEditReview(created, now: created.add(const Duration(hours: 24))),
        isFalse,
      );
    });

    test('button labels change after a review exists', () {
      expect(reviewActionKind(null), ReviewActionKind.leave);
      expect(
        reviewActionLabel(ReviewActionKind.leave, ratingBuyer: false),
        'Leave a Review',
      );
      expect(
        reviewActionLabel(ReviewActionKind.leave, ratingBuyer: true),
        'Rate Buyer',
      );

      final review = ReviewModel.fromSupabase({
        'review_id': 'r1',
        'order_id': 'o1',
        'reviewer_id': 'buyer-1',
        'reviewed_user_id': 'seller-1',
        'rating': 5,
        'review_text': 'On time',
        'review_type': 'buyer_to_seller',
        'created_at': '2026-09-13T01:00:00Z',
      });
      expect(
        reviewActionKind(review, now: DateTime.parse('2026-09-13T02:00:00Z')),
        ReviewActionKind.edit,
      );
      expect(
        reviewActionKind(review, now: DateTime.parse('2026-09-14T02:00:00Z')),
        ReviewActionKind.view,
      );
    });

    test('shows no reviews yet when the count is zero', () {
      expect(formatRatingAverage(average: 4.8, count: 0), 'No reviews yet');
      expect(formatRatingAverage(average: 4.8, count: 0, compact: true), '—');
      expect(formatRatingAverage(average: 4.8, count: 3), '4.8');
    });
  });

  group('review mapping', () {
    test('maps buyer and seller review directions', () {
      final buyerReview = ReviewModel.fromSupabase({
        'review_id': 'r1',
        'order_id': 'o1',
        'reviewer_id': 'buyer-1',
        'reviewed_user_id': 'seller-1',
        'rating': 4,
        'review_text': 'Nice item',
        'review_type': 'buyer_to_seller',
        'created_at': '2026-09-13T01:00:00Z',
        'reviewer': {
          'username': 'maya',
          'full_name': 'Maya Cruz',
          'avatar': '',
        },
      });
      expect(buyerReview.reviewType, 'buyer_to_seller');
      expect(buyerReview.reviewerUsername, 'maya');
      expect(buyerReview.comment, 'Nice item');

      final sellerReview = ReviewModel.fromSupabase({
        'review_id': 'r2',
        'order_id': 'o1',
        'reviewer_id': 'seller-1',
        'reviewed_user_id': 'buyer-1',
        'rating': 5,
        'review_text': '',
        'review_type': 'seller_to_buyer',
        'created_at': '2026-09-13T01:10:00Z',
      });
      expect(sellerReview.reviewType, 'seller_to_buyer');
      expect(sellerReview.reviewedUserId, 'buyer-1');
    });
  });

  group('completed-order review gate', () {
    OrderModel order(String status) {
      return OrderModel.fromSupabase({
        'order_id': 'order-1',
        'order_number': 'TL-8',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': status,
        'subtotal': 400,
        'shipping_fee': 80,
        'platform_fee': 8,
        'total_amount': 488,
        'created_at': '2026-09-13T02:00:00Z',
      });
    }

    test('only completed orders are reviewable in the UI', () {
      expect(order('completed').isCompleted, isTrue);
      expect(order('shipped').isCompleted, isFalse);
      expect(order('paid').isCompleted, isFalse);
      expect(order('pending').isCompleted, isFalse);
      expect(order('cancelled').isCompleted, isFalse);
      expect(orderStatusFromDb('completed'), OrderStatus.completed);
    });
  });

  group('community reports', () {
    test('preserves existing report reason slugs', () {
      expect(kReportReasons.map((r) => r.slug), contains('scam_or_fraud'));
      expect(kReportReasons.map((r) => r.slug), contains('harassment'));
      expect(kReportReasons.map((r) => r.slug), contains('other'));
      expect(reportReasonLabel('fake_product'), 'Fake or Misrepresented Item');
    });

    test('maps studio statuses to readable labels', () {
      expect(reportStatusLabel('under_review'), 'Under Review');
      expect(reportStatusLabel('action_taken'), 'Action Taken');
      expect(reportStatusLabel('resolved'), 'Resolved');
      expect(reportStatusLabel('dismissed'), 'Dismissed');
    });

    test('requires a reasonable details length', () {
      expect(reportDetailsError('too short'), isNotNull);
      expect(
        reportDetailsError('Received a different item than listed.'),
        isNull,
      );
      expect(reportDetailsError('a' * 2001), isNotNull);
    });

    test('requires one to three evidence photos', () {
      expect(kReportEvidenceMinCount, 1);
      expect(kReportEvidenceMaxCount, 3);
    });

    test('maps delivery dispute reasons to report categories', () {
      expect(
        deliveryDisputeReportCategory(DeliveryDisputeReason.damagedItem),
        'item_not_as_described',
      );
      expect(
        deliveryDisputeReportCategory(DeliveryDisputeReason.wrongItem),
        'fake_product',
      );
    });

    test('accepts only photo evidence names', () {
      expect(isAllowedReportImageName('chat.png'), isTrue);
      expect(isAllowedReportImageName('proof.JPG'), isTrue);
      expect(isAllowedReportImageName('notes.pdf'), isFalse);
      expect(isAllowedReportImageName('payload.exe'), isFalse);
      expect(reportImageContentType('shot.webp'), 'image/webp');
    });

    test('maps a persisted report without exposing extra fields', () {
      final report = CommunityReportModel.fromSupabase(
        {
          'report_id': 'rpt-1',
          'reporter_id': 'buyer-1',
          'reported_user_id': 'seller-1',
          'category': 'scam_or_fraud',
          'details': 'Asked me to pay outside the app.',
          'status': 'under_review',
          'admin_response': null,
          'created_at': '2026-09-13T03:00:00Z',
        },
        reportedUser: {
          'username': 'vintagevibes_ph',
          'full_name': 'Vintage Shop',
        },
        orderNumber: 'TL-8',
      );
      expect(report.status, 'under_review');
      expect(report.reportedUsername, 'vintagevibes_ph');
      expect(report.orderNumber, 'TL-8');
      expect(report.adminResponse, isNull);
    });
  });
}
