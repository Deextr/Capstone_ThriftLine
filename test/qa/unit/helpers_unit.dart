import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thriftline/core/utils/extensions.dart';
import 'package:thriftline/core/utils/saved_items_eligibility.dart';
import 'package:thriftline/core/utils/supabase_errors.dart';
import 'package:thriftline/features/trust_safety/data/review_rules.dart';

import '../support/qa_reporter.dart';

void helpersUnitTests() {
  qaGroup('String extensions', () {
    qaUnitTest('capitalize upper-cases only the first letter', () {
      expect('thrift'.capitalize, 'Thrift');
      expect('tHRIFT'.capitalize, 'THRIFT');
      expect(''.capitalize, '');
    });

    qaUnitTest('null/empty helpers', () {
      String? nothing;
      expect(nothing.isNullOrEmpty, isTrue);
      expect(''.isNullOrEmpty, isTrue);
      expect('x'.isNullOrEmpty, isFalse);
      expect('x'.isNotNullOrEmpty, isTrue);
    });
  });

  qaGroup('Saved items eligibility', () {
    qaUnitTest('favorite shows only for buyers viewing others', () {
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: true,
          viewerUserId: 'buyer',
          productSellerId: 'seller',
        ),
        isTrue,
      );
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: false,
          viewerUserId: 'buyer',
          productSellerId: 'seller',
        ),
        isFalse,
      );
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: true,
          viewerUserId: 'seller',
          productSellerId: 'seller',
        ),
        isFalse,
      );
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: true,
          viewerUserId: null,
          productSellerId: 'seller',
        ),
        isFalse,
      );
    });

    qaUnitTest('users cannot persist saves on their own listing', () {
      expect(
        canPersistProductSave(viewerUserId: 'a', productSellerId: 'b'),
        isTrue,
      );
      expect(
        canPersistProductSave(viewerUserId: 'a', productSellerId: 'a'),
        isFalse,
      );
      expect(
        canPersistProductSave(viewerUserId: 'a', productSellerId: ''),
        isFalse,
      );
    });
  });

  qaGroup('Supabase errors', () {
    const denied = PostgrestException(
      message: 'permission denied for table orders',
      code: '42501',
    );
    const deniedShipments = PostgrestException(
      message: 'permission denied for table shipments',
      code: '42501',
    );
    const notFound = PostgrestException(message: 'not found', code: 'PGRST116');

    qaUnitTest('detects permission-denied by code or message', () {
      expect(isPostgrestPermissionDenied(denied), isTrue);
      expect(
        isPostgrestPermissionDenied(
          const PostgrestException(message: 'x', code: '403'),
        ),
        isTrue,
      );
      expect(
        isPostgrestPermissionDenied(
          const PostgrestException(message: 'Forbidden'),
        ),
        isTrue,
      );
      expect(isPostgrestPermissionDenied(notFound), isFalse);
    });

    qaUnitTest('detects likely network errors', () {
      expect(
        isLikelyNetworkError(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(isLikelyNetworkError('Connection timed out'), isTrue);
      expect(isLikelyNetworkError(Exception('Something else')), isFalse);
    });

    qaUnitTest('userFacingOrderLoadError never leaks raw SQL', () {
      expect(
        userFacingOrderLoadError(denied),
        "We couldn't load your orders right now. Please try again later.",
      );
      expect(
        userFacingOrderLoadError(Exception('SocketException')),
        'Unable to load orders. Please check your connection and try again.',
      );
      expect(
        userFacingOrderLoadError(notFound),
        'Unable to load orders. Please try again.',
      );
      expect(
        userFacingOrderLoadError(notFound, fallback: 'Custom'),
        'Custom',
      );
    });

    qaUnitTest('shipment fallback only for denied shipment selects', () {
      expect(orderSelectMightNeedShipmentFallback(deniedShipments), isTrue);
      expect(orderSelectMightNeedShipmentFallback(denied), isFalse);
      expect(
        orderSelectMightNeedShipmentFallback(
          const PostgrestException(message: 'shipments missing'),
        ),
        isFalse,
      );
    });
  });

  qaGroup('Review rules', () {
    final createdAt = DateTime(2026, 10, 1, 9);

    qaUnitTest('reviews are editable for 24 hours', () {
      expect(
        canEditReview(
          createdAt,
          now: createdAt.add(const Duration(hours: 23, minutes: 59)),
        ),
        isTrue,
      );
      expect(
        canEditReview(createdAt, now: createdAt.add(const Duration(hours: 24))),
        isFalse,
      );
    });

    qaUnitTest('no existing review means "leave"', () {
      expect(reviewActionKind(null), ReviewActionKind.leave);
    });

    qaUnitTest('action labels and prompts depend on who is rated', () {
      expect(
        reviewActionLabel(ReviewActionKind.leave, ratingBuyer: true),
        'Rate Buyer',
      );
      expect(
        reviewActionLabel(ReviewActionKind.leave, ratingBuyer: false),
        'Leave a Review',
      );
      expect(
        reviewActionLabel(ReviewActionKind.edit, ratingBuyer: false),
        'Edit Review',
      );
      expect(
        reviewActionLabel(ReviewActionKind.view, ratingBuyer: true),
        'View Review',
      );
      expect(
        reviewPrompt(ratingBuyer: true),
        'How was your experience with this buyer?',
      );
      expect(
        reviewPrompt(ratingBuyer: false),
        'How was your experience with this seller?',
      );
    });

    qaUnitTest('formatRatingAverage handles no reviews', () {
      expect(formatRatingAverage(count: 0), 'No reviews yet');
      expect(formatRatingAverage(count: 0, compact: true), '—');
      expect(formatRatingAverage(average: 4.66, count: 3), '4.7');
      expect(formatRatingAverage(count: 2), '0.0');
    });

    qaUnitTest('rating must be between 1 and 5', () {
      const message = 'Choose a rating from 1 to 5 stars.';
      expect(reviewRatingError(0), message);
      expect(reviewRatingError(6), message);
      expect(reviewRatingError(1), isNull);
      expect(reviewRatingError(5), isNull);
    });

    qaUnitTest('comment is limited to 1,000 trimmed characters', () {
      expect(
        reviewCommentError('a' * 1001),
        'Keep your comment under 1,000 characters.',
      );
      expect(reviewCommentError('  ${'a' * 1000}  '), isNull);
      expect(reviewCommentError(''), isNull);
    });
  });
}
