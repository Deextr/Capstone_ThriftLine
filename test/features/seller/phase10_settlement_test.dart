import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/features/admin/data/delivery_payment_hold.dart';
import 'package:thriftline/features/admin/data/delivery_payment_resolve.dart';
import 'package:thriftline/features/seller/data/seller_earnings.dart';
import 'package:thriftline/features/trust_safety/data/report_appeal.dart';
import 'package:thriftline/models/notification_model.dart';

void main() {
  group('financial hold mapping', () {
    test('a paid hold is not seller earnings yet', () {
      final hold = DeliveryPaymentHold.fromSupabase({
        'escrow_id': 'e1',
        'order_id': 'o1',
        'status': 'held',
        'amount_centavos': 50000,
        'seller_amount_centavos': 49000,
      });
      expect(hold.canDecide, isTrue);
      expect(hold.isReleased, isFalse);
      expect(canResolveDeliveryPayment('held'), isTrue);
      expect(deliveryHoldStatusLabel('held'), 'Payment held');
    });

    test('released and refunded cannot reverse', () {
      expect(canResolveDeliveryPayment('released'), isFalse);
      expect(canResolveDeliveryPayment('refunded'), isFalse);
      expect(isFinancialDeliveryDecision('release'), isTrue);
      expect(isFinancialDeliveryDecision('refund'), isTrue);
    });
  });

  group('seller earnings snapshot', () {
    test('uses server balances and does not hardcode dashboard totals', () {
      final snapshot = SellerEarningsSnapshot.fromMap({
        'success': true,
        'held_centavos': 50000,
        'released_centavos': 120000,
        'refunded_centavos': 30000,
        'payout_requested_centavos': 0,
        'available_centavos': 120000,
        'listing_count': 4,
        'activity': [
          {
            'escrow_id': 'e1',
            'order_id': 'o1',
            'order_number': 'TL-1234',
            'title': 'Vintage Lacoste Polo',
            'status': 'released',
            'seller_amount_centavos': 55000,
            'sort_at': '2026-09-14T03:00:00Z',
          },
        ],
        'payouts': const [],
      });
      expect(snapshot.heldCentavos, 50000);
      expect(snapshot.releasedCentavos, 120000);
      expect(snapshot.refundedCentavos, 30000);
      expect(snapshot.availableCentavos, 120000);
      expect(formatCentavos(snapshot.heldCentavos), contains('500'));
      expect(formatCentavos(snapshot.availableCentavos), contains('1,200'));
      expect(snapshot.activity.first.title, 'Vintage Lacoste Polo');
      expect(snapshot.activity.first.status, isNot('fake'));
    });

    test('available earnings subtract committed payouts', () {
      expect(
        sellerAvailableCentavos(
          releasedCentavos: 120000,
          payoutRequestedCentavos: 0,
        ),
        120000,
      );
      expect(
        sellerAvailableCentavos(
          releasedCentavos: 120000,
          payoutRequestedCentavos: 120000,
        ),
        0,
      );
      expect(
        sellerAvailableCentavos(
          releasedCentavos: 50000,
          payoutRequestedCentavos: 80000,
        ),
        0,
      );
    });

    test('rejects an excessive or duplicate payout amount', () {
      expect(sellerPayoutAmountAllowed(120000, 120000), isTrue);
      expect(sellerPayoutAmountAllowed(500000, 120000), isFalse);
      expect(sellerPayoutAmountAllowed(120000, 0), isFalse);
      expect(sellerPayoutAmountAllowed(50, 120000), isFalse);
    });

    test('prefers the server available_centavos field', () {
      final snapshot = SellerEarningsSnapshot.fromMap({
        'held_centavos': 0,
        'released_centavos': 120000,
        'refunded_centavos': 0,
        'payout_requested_centavos': 20000,
        'available_centavos': 100000,
      });
      expect(snapshot.availableCentavos, 100000);
    });
  });

  group('admin refund copy', () {
    test('does not claim PayMongo success for an internal refund', () {
      expect(
        refundProviderMessage('paymongo'),
        'Refund sent through the original payment method.',
      );
      expect(
        refundProviderMessage('internal'),
        contains('did not process an automatic refund'),
      );
      expect(refundBuyerCtaLabel(55000), contains('Refund'));
      expect(refundBuyerCtaLabel(55000), contains('550'));
      expect(releaseSellerCtaLabel(55000), contains('Release'));
    });

    test('parses a refund function result without inventing a provider id', () {
      final result = DeliveryPaymentResult.fromMap({
        'success': true,
        'decision': 'refund',
        'status': 'refunded',
        'refund_provider': 'internal',
        'amount_centavos': 55000,
      });
      expect(result.success, isTrue);
      expect(result.refundProvider, 'internal');
      expect(result.amountCentavos, 55000);
    });
  });

  group('community reports stay off the money path', () {
    test('Action Taken does not count as a financial decision', () {
      expect(isFinancialDeliveryDecision('action_taken'), isFalse);
      expect(communityReportDecisionMovesMoney('action_taken'), isFalse);
      expect(communityReportDecisionMovesMoney('resolved'), isFalse);
      expect(communityReportDecisionMovesMoney('dismissed'), isFalse);
    });
  });

  group('reported-user notice and appeal', () {
    test('parses notification data and hides reporter taps', () {
      const reportId = '11111111-1111-4111-8111-111111111111';
      final reported = NotificationModel.fromJson({
        'notification_id': 'n1',
        'user_id': 'u1',
        'type': 'system',
        'title': 'Account review update',
        'body':
            'A community report involving your account has been reviewed. Reporter details are not shared.',
        'created_at': '2026-09-14T03:00:00Z',
        'data': {'report_id': reportId, 'can_appeal': true},
      });
      expect(reported.data['report_id'], reportId);
      expect(notificationAppealReportId(reported.data), reportId);

      final reporter = NotificationModel.fromJson({
        'notification_id': 'n2',
        'user_id': 'u2',
        'type': 'report_decision',
        'title': 'Report update',
        'body': 'We reviewed your report.',
        'created_at': '2026-09-14T03:00:00Z',
        'data': {'report_id': reportId, 'status': 'action_taken'},
      });
      expect(notificationAppealReportId(reporter.data), isNull);
    });

    test(
      'appeal copy stays within length bounds and ignores reporter fields',
      () {
        expect(appealDetailsError('short'), isNotNull);
        expect(
          appealDetailsError('Please take another look at this decision.'),
          isNull,
        );
        expect(appealDetailsError('a' * 2001), isNotNull);

        final context = ReportAppealContext.fromMap({
          'success': true,
          'can_appeal': true,
          'already_submitted': false,
          'under_review': false,
          'reporter_id': 'should-not-be-required',
          'reporter_username': 'maya',
        });
        expect(context.canAppeal, isTrue);
        expect(context.details, isNull);
      },
    );
  });

  group('escrow status labels', () {
    test('uses human wording instead of legal escrow claims', () {
      expect(sellerEscrowStatusLabel('held'), 'Earnings pending');
      expect(sellerEscrowStatusHint('held'), contains('completion'));
      expect(sellerEscrowStatusLabel('released'), 'Available');
      expect(sellerEscrowStatusLabel('refunded'), 'Refunded');
      expect(deliveryHoldStatusLabel('held'), isNot(contains('escrow')));
    });
  });
}
