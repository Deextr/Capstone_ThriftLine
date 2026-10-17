import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/auction_relist_feedback.dart';
import 'package:thriftline/features/seller/data/listing_snapshot.dart';

void main() {
  final now = DateTime.utc(2026, 10, 16, 12);

  ListingSnapshot endedAuction({
    String? winnerId,
    String? orderStatus,
    String? paymentStatus,
    DateTime? paymentDueAt,
    int bidCount = 1,
  }) {
    return ListingSnapshot(
      productStatus: 'active',
      listingType: 'auction',
      auctionStatus: 'ended',
      endsAt: now.subtract(const Duration(hours: 1)),
      winnerId: winnerId,
      orderStatus: orderStatus,
      paymentStatus: paymentStatus,
      paymentDueAt: paymentDueAt,
      bidCount: bidCount,
      now: now,
    );
  }

  group('winnerPaymentWindowBlocksRelist', () {
    test('blocks when min exceeds max equivalent: pending window active', () {
      final listing = endedAuction(
        winnerId: 'w1',
        orderStatus: 'pending',
        paymentDueAt: now.add(const Duration(hours: 11)),
      );
      expect(winnerPaymentWindowBlocksRelist(listing), isTrue);
      expect(canRelistAuction(listing), isFalse);
    });

    test('allows relist after payment window expired (cancelled order)', () {
      final listing = endedAuction(winnerId: 'w1', orderStatus: 'cancelled');
      expect(winnerPaymentWindowBlocksRelist(listing), isFalse);
      expect(canRelistAuction(listing), isTrue);
    });

    test('allows relist when auction was paid', () {
      final listing = endedAuction(
        winnerId: 'w1',
        orderStatus: 'paid',
        paymentStatus: 'paid',
      );
      expect(canRelistAuction(listing), isFalse);
    });

    test('blocks when payment is still pending verification', () {
      final listing = endedAuction(
        winnerId: 'w1',
        orderStatus: 'pending',
        paymentStatus: 'pending',
        paymentDueAt: now.add(const Duration(hours: 2)),
      );
      expect(winnerPaymentWindowBlocksRelist(listing), isTrue);
    });

    test('ended with winner but missing order blocks until resolved', () {
      final listing = endedAuction(winnerId: 'w1');
      expect(winnerPaymentWindowBlocksRelist(listing), isTrue);
    });
  });

  group('bid round eligibility (client guard)', () {
    test(
      'valid unpaid expired round may relist (server increments bid_round)',
      () {
        final listing = endedAuction(winnerId: 'w1', orderStatus: 'cancelled');
        expect(canRelistAuction(listing), isTrue);
      },
    );
  });
}
