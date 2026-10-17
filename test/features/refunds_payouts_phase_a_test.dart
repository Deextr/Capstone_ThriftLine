import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/delivery_payment_hold.dart';
import 'package:thriftline/features/admin/data/delivery_payment_resolve.dart';
import 'package:thriftline/features/admin/domain/admin_order_management.dart';
import 'package:thriftline/features/admin/domain/admin_refund.dart';
import 'package:thriftline/features/admin/data/seller_payout_rejection_reasons.dart';
import 'package:thriftline/features/admin/domain/admin_seller_payout.dart';
import 'package:thriftline/features/buyer/data/buyer_transaction.dart';
import 'package:thriftline/features/seller/data/seller_earnings.dart';

Map<String, dynamic> _txn({
  String paymentStatus = 'paid',
  String? refundState,
  String? link,
}) => {
  'payment_id': 'p1',
  'order_id': 'o1',
  'order_number': 'TL-1',
  'product_title': 'Denim jacket',
  'payment_status': paymentStatus,
  'amount_centavos': 125000,
  'paymongo_channel': 'qrph',
  'refund_state': refundState,
  'refund_transfer_link': link,
};

void main() {
  group('buyer refund status', () {
    test('a refund in progress is not shown as refunded', () {
      for (final state in [
        'provider_pending',
        'awaiting_buyer_claim',
        'manual_required',
      ]) {
        final t = BuyerTransaction.fromJson(_txn(refundState: state));
        expect(
          t.status,
          BuyerTransactionStatus.refundInProgress,
          reason: state,
        );
        expect(buyerTransactionStatusLabel(t.status), 'Refund in progress');
      }
    });

    test('only confirmed refunds count as refunded', () {
      expect(
        BuyerTransaction.fromJson(_txn(refundState: 'succeeded')).status,
        BuyerTransactionStatus.refunded,
      );
      expect(
        BuyerTransaction.fromJson(_txn(refundState: 'manual_completed')).status,
        BuyerTransactionStatus.refunded,
      );
      expect(
        BuyerTransaction.fromJson(_txn(paymentStatus: 'refunded')).status,
        BuyerTransactionStatus.refunded,
      );
      expect(
        BuyerTransaction.fromJson(_txn()).status,
        BuyerTransactionStatus.successful,
      );
    });

    test('the Refunds filter includes refunds in progress', () {
      final pending = BuyerTransaction.fromJson(
        _txn(refundState: 'provider_pending'),
      );
      expect(
        buyerTransactionMatchesFilter(pending, BuyerTransactionFilter.refunded),
        isTrue,
      );
      expect(
        buyerTransactionMatchesFilter(
          pending,
          BuyerTransactionFilter.successful,
        ),
        isFalse,
      );
    });

    test('manual refunds do not expose a claim link', () {
      final t = BuyerTransaction.fromJson(
        _txn(refundState: 'manual_required', link: 'https://example.com/x'),
      );
      expect(t.refundClaimLink, isNull);
    });

    test('a claim link is shown only while waiting for the buyer', () {
      const link = 'https://pm.link/claim/abc';
      expect(
        BuyerTransaction.fromJson(
          _txn(refundState: 'awaiting_buyer_claim', link: link),
        ).refundClaimLink,
        link,
      );
      expect(
        BuyerTransaction.fromJson(
          _txn(refundState: 'provider_pending', link: link),
        ).refundClaimLink,
        isNull,
      );
      expect(safeRefundClaimLink('http://pm.link/claim'), isNull);
      expect(safeRefundClaimLink('javascript:alert(1)'), isNull);
      expect(safeRefundClaimLink(''), isNull);
    });

    test('asks for GCash only when a manual refund is needed', () {
      final manual = BuyerTransaction.fromJson(
        _txn(refundState: 'manual_required'),
      );
      expect(manual.needsGcashDetails, isTrue);
      final pending = BuyerTransaction.fromJson(
        _txn(refundState: 'provider_pending'),
      );
      expect(pending.needsGcashDetails, isFalse);
    });

    test('QR Ph is labelled as the payment method', () {
      expect(
        buyerPaymentMethodLabel(paymentMethod: null, paymongoChannel: 'qrph'),
        'QR Ph',
      );
    });

    test('validates GCash details', () {
      expect(normalizePhMobileNumber('+63 917 123 4567'), '09171234567');
      expect(normalizePhMobileNumber('639171234567'), '09171234567');
      expect(normalizePhMobileNumber('0917-123-4567'), '09171234567');
      expect(normalizePhMobileNumber('12345'), isNull);
      expect(validateGcashMobileNumber('09171234567'), isNull);
      expect(validateGcashMobileNumber('0817123456'), isNotNull);
      expect(validateGcashAccountName('J'), isNotNull);
      expect(validateGcashAccountName('Juan Dela Cruz'), isNull);
      expect(validateGcashAccountName('a' * 81), isNotNull);
    });
  });

  group('seller payouts', () {
    test('available balance subtracts requested and paid payouts', () {
      expect(
        sellerAvailableCentavos(
          releasedCentavos: 100000,
          payoutRequestedCentavos: 20000,
          payoutPaidCentavos: 30000,
        ),
        50000,
      );
      expect(
        sellerAvailableCentavos(
          releasedCentavos: 1000,
          payoutRequestedCentavos: 800,
          payoutPaidCentavos: 800,
        ),
        0,
      );
    });

    test('an open request blocks a second request', () {
      final snapshot = SellerEarningsSnapshot.fromMap({
        'released_centavos': 100000,
        'payout_requested_centavos': 20000,
        'available_centavos': 80000,
        'payouts': [
          {'payout_id': 'x', 'amount_centavos': 20000, 'status': 'requested'},
        ],
      });
      expect(snapshot.hasOpenPayout, isTrue);
      expect(snapshot.canRequestPayout, isFalse);
      expect(snapshot.openPayout!.canCancel, isTrue);
    });

    test('maps payout statuses with honest labels', () {
      expect(sellerPayoutStatusFromRaw('paid'), SellerPayoutStatus.paid);
      expect(
        sellerPayoutStatusFromRaw('cancelled'),
        SellerPayoutStatus.cancelled,
      );
      expect(
        sellerPayoutStatusLabel(SellerPayoutStatus.requested),
        'Waiting for admin',
      );
      expect(sellerPayoutStatusLabel(SellerPayoutStatus.paid), 'Sent to GCash');
      expect(maskMobileNumber('09171234567'), '•••• 4567');
      expect(maskMobileNumber(null), '');
    });

    test('resolves predefined payout rejection reasons for the seller', () {
      expect(
        sellerPayoutRejectionReasonMessage(reasonId: 'invalid_gcash'),
        isNotNull,
      );
      expect(
        sellerPayoutRejectionReasonMessage(
          reasonId: kSellerPayoutRejectOtherId,
          otherDetail: 'Please use the GCash number on your profile.',
        ),
        'Please use the GCash number on your profile.',
      );
      expect(validatePayoutRejectionSelection(reasonId: null), isNotNull);
      expect(
        validatePayoutRejectionSelection(
          reasonId: kSellerPayoutRejectOtherId,
          otherDetail: 'abc',
        ),
        isNotNull,
      );
      expect(
        validatePayoutRejectionSelection(
          reasonId: kSellerPayoutRejectOtherId,
          otherDetail: 'Please update your GCash details.',
        ),
        isNull,
      );
      expect(
        validatePayoutRejectionSelection(reasonId: 'name_mismatch'),
        isNull,
      );
    });
  });

  group('admin payout transfer validation', () {
    test('parses peso amounts into centavos', () {
      expect(parsePesoToCentavos('1250'), 125000);
      expect(parsePesoToCentavos('1,250.5'), 125050);
      expect(parsePesoToCentavos('₱ 1,250.50'), 125050);
      expect(parsePesoToCentavos('12.345'), isNull);
      expect(parsePesoToCentavos('abc'), isNull);
      expect(parsePesoToCentavos(''), isNull);
    });

    test('the amount sent must match exactly', () {
      expect(validateTransferAmount('1250.00', 125000), isNull);
      expect(validateTransferAmount('1249.99', 125000), isNotNull);
      expect(validateTransferAmount('', 125000), isNotNull);
    });

    test('requires a reference and a past date', () {
      expect(validateTransferReference(''), isNotNull);
      expect(validateTransferReference('123'), isNotNull);
      expect(validateTransferReference('1234567890'), isNull);
      final now = DateTime(2026, 10, 16, 12);
      expect(validateTransferDate(null, now: now), isNotNull);
      expect(
        validateTransferDate(now.add(const Duration(days: 1)), now: now),
        isNotNull,
      );
      expect(validateTransferDate(now, now: now), isNull);
    });

    test('parses an admin payout row', () {
      final payout = AdminSellerPayout.fromMap({
        'payout_id': 'p1',
        'seller_id': 's1',
        'seller_name': 'Ana',
        'shop_name': 'Ana Thrift',
        'amount_centavos': 50000,
        'status': 'requested',
        'gcash_account_name': 'Ana Cruz',
        'gcash_mobile_number': '09171234567',
      });
      expect(payout.isOpen, isTrue);
      expect(payout.hasGcashDestination, isTrue);
      expect(payout.sellerDisplayName, 'Ana Thrift');
      expect(AdminPayoutStatusFilter.all.rpcValue, isNull);
      expect(AdminPayoutStatusFilter.requested.rpcValue, 'requested');
    });
  });

  group('admin refund state', () {
    test('order status reflects where the refund stands', () {
      String label(String? refundState, {String payment = 'paid'}) =>
          adminUnifiedOrderStatus(
            orderStatusDb: 'cancelled',
            paymentStatus: payment,
            escrowStatus: 'refunded',
            refundState: refundState,
          ).label;

      expect(label('provider_pending'), 'Refund processing');
      expect(label('awaiting_buyer_claim'), contains('claim'));
      expect(label('manual_required'), 'Refund needs action');
      expect(label('succeeded', payment: 'refunded'), 'Cancelled · Refunded');
    });

    test('reads refund tracking fields from the escrow row', () {
      final hold = DeliveryPaymentHold.fromSupabase({
        'escrow_id': 'e1',
        'order_id': 'o1',
        'buyer_id': 'b1',
        'status': 'refunded',
        'amount_centavos': 125000,
        'seller_amount_centavos': 110000,
        'refund_state': 'manual_required',
        'refund_lock_at': '2026-10-16T01:00:00Z',
      });
      expect(hold.refundNeedsManualAction, isTrue);
      expect(hold.refundLocked, isTrue);
      expect(hold.refundIsComplete, isFalse);
      expect(adminRefundStateHint(hold), contains('GCash'));
    });

    test('refund copy never claims success before confirmation', () {
      expect(
        refundProviderMessage('paymongo', refundState: 'provider_pending'),
        'PayMongo is still processing this refund.',
      );
      expect(
        refundProviderMessage('internal', refundState: 'manual_required'),
        contains('manual GCash refund'),
      );
      expect(
        refundProviderMessage('paymongo', refundState: 'succeeded'),
        'PayMongo returned the payment to the buyer.',
      );
    });

    test('dispute result carries the refund state', () {
      final result = DeliveryPaymentResult.fromMap({
        'success': true,
        'refund_provider': 'paymongo',
        'refund_state': 'awaiting_buyer_claim',
      });
      expect(result.refundState, 'awaiting_buyer_claim');
    });

    test('reconcile results are explained plainly', () {
      final failed = adminRefundActionResultFromMap({
        'success': false,
        'error': 'PayMongo could not be checked.',
      }, action: 'check');
      expect(failed.success, isFalse);
      expect(failed.message, 'PayMongo could not be checked.');

      final none = adminRefundActionResultFromMap({
        'success': true,
        'verified_no_refund': true,
        'refund_state': 'manual_required',
      }, action: 'check');
      expect(none.message, contains('no refund'));

      final refused = adminRefundActionResultFromMap({
        'success': true,
        'rejected': true,
        'error_code': 'insufficient_balance',
      }, action: 'retry');
      expect(refused.message, contains('insufficient_balance'));

      final unreachable = adminRefundActionResultFromMap(null, action: 'retry');
      expect(unreachable.success, isFalse);
      expect(unreachable.message, contains('Nothing was changed'));
    });

    test('labels refund attempts', () {
      final attempt = AdminRefundAttempt.fromMap({
        'created_at': '2026-10-16T02:00:00Z',
        'source': 'admin_retry',
        'action': 'create',
        'outcome': 'unknown',
        'http_status': 502,
      });
      expect(attempt.title, contains('no confirmed answer'));
      expect(attempt.detail, contains('HTTP 502'));
    });

    test('QR Ph channel label', () {
      expect(adminPaymongoChannelLabel('qrph'), 'QR Ph (PayMongo)');
    });
  });
}
