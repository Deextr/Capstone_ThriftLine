import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/listing_bucket.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  ListingSnapshot auction({
    String productStatus = 'active',
    String? auctionStatus = 'ended',
    DateTime? endsAt,
    String? winnerId,
    String? orderStatus,
    String? paymentStatus,
    DateTime? paymentDueAt,
    int bidCount = 0,
  }) {
    return ListingSnapshot(
      productStatus: productStatus,
      listingType: 'auction',
      auctionStatus: auctionStatus,
      endsAt: endsAt ?? now.subtract(const Duration(hours: 1)),
      winnerId: winnerId,
      orderStatus: orderStatus,
      paymentStatus: paymentStatus,
      paymentDueAt: paymentDueAt,
      bidCount: bidCount,
      now: now,
    );
  }

  test('zero bids stays unsold and inactive', () {
    final listing = auction();
    expect(listingBucketFor(listing), ListingBucket.inactive);
    expect(canRelistAuction(listing), isTrue);
    expect(canEditListing(listing), isFalse);
  });

  test('stale active past ends_at is inactive but relistable', () {
    final listing = auction(
      auctionStatus: 'active',
      endsAt: now.subtract(const Duration(hours: 2)),
    );
    expect(listingBucketFor(listing), ListingBucket.inactive);
    expect(canRelistAuction(listing), isTrue);
  });

  test('active fixed-price listing can be edited', () {
    final listing = ListingSnapshot(
      productStatus: 'active',
      listingType: 'fixed_price',
      now: now,
    );
    expect(listingBucketFor(listing), ListingBucket.active);
    expect(canEditListing(listing), isTrue);
  });

  test('paid auction is sold', () {
    final listing = auction(
      productStatus: 'sold',
      winnerId: 'winner',
      orderStatus: 'paid',
      paymentStatus: 'paid',
    );
    expect(listingBucketFor(listing), ListingBucket.sold);
    expect(canRelistAuction(listing), isFalse);
  });

  test('winner inside the payment window is awaiting payment', () {
    final listing = auction(
      winnerId: 'first',
      orderStatus: 'pending',
      paymentStatus: 'pending',
      paymentDueAt: now.add(const Duration(hours: 6)),
    );
    expect(listingBucketFor(listing), ListingBucket.awaitingPayment);
  });

  test('second bidder keeps the same awaiting-payment bucket', () {
    final listing = auction(
      winnerId: 'second',
      orderStatus: 'pending',
      paymentStatus: 'pending',
      paymentDueAt: now.add(const Duration(hours: 12)),
    );
    expect(listingBucketFor(listing), ListingBucket.awaitingPayment);
  });

  test('both payment windows missed is inactive', () {
    final listing = auction(orderStatus: 'cancelled');
    expect(listingBucketFor(listing), ListingBucket.inactive);
    expect(canRelistAuction(listing), isTrue);
  });

  test('live auction with a bid can end early', () {
    final listing = auction(
      auctionStatus: 'active',
      endsAt: now.add(const Duration(hours: 4)),
      bidCount: 2,
    );
    expect(listingBucketFor(listing), ListingBucket.active);
    expect(canEndAuctionEarly(listing), isTrue);
  });

  test('live auction with no bids cannot end early', () {
    final listing = auction(
      auctionStatus: 'active',
      endsAt: now.add(const Duration(hours: 4)),
    );
    expect(canEndAuctionEarly(listing), isFalse);
  });

  test('fixed-price active listing stays active', () {
    final listing = ListingSnapshot(
      productStatus: 'active',
      listingType: 'fixed_price',
      now: now,
    );
    expect(listingBucketFor(listing), ListingBucket.active);
  });

  test('seller manual next-bidder offer is disabled (automatic fallback)', () {
    final listing = auction(orderStatus: 'cancelled', bidCount: 3);
    expect(canOfferToNextBidder(listing), isFalse);
    expect(canRelistAuction(listing), isTrue);
  });
}
