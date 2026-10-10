import 'listing_snapshot.dart';

export 'auction_relist_feedback.dart'
    show auctionRelistHint, auctionRelistMessageFromRpc, canRelistAuction;
export 'listing_snapshot.dart';

/// Display buckets for My Listings. These do not add a product status.
enum ListingBucket { active, awaitingPayment, sold, inactive }

ListingBucket listingBucketFor(ListingSnapshot listing) {
  if (listing.productStatus == 'sold' || listing.paymentStatus == 'paid') {
    return ListingBucket.sold;
  }

  if (listing.listingType != 'auction') {
    return listing.productStatus == 'active'
        ? ListingBucket.active
        : ListingBucket.inactive;
  }

  final stillLive =
      listing.auctionStatus == 'active' &&
      listing.endsAt != null &&
      listing.endsAt!.isAfter(listing.now);
  if (stillLive) return ListingBucket.active;

  final winner = listing.winnerId != null && listing.winnerId!.isNotEmpty;
  final unpaid =
      listing.orderStatus == 'pending' && listing.paymentStatus != 'paid';
  final windowOpen =
      listing.paymentDueAt != null &&
      listing.paymentDueAt!.isAfter(listing.now);
  if (listing.auctionStatus == 'ended' && winner && unpaid && windowOpen) {
    return ListingBucket.awaitingPayment;
  }

  return ListingBucket.inactive;
}

bool canEndAuctionEarly(ListingSnapshot listing) {
  if (listing.listingType != 'auction') return false;
  if (listing.auctionStatus != 'active') return false;
  if (listing.endsAt == null || !listing.endsAt!.isAfter(listing.now)) {
    return false;
  }
  return listing.bidCount >= 1;
}

/// Fallback to the second-highest bidder is automatic after the primary
/// winner's payment window expires. Sellers do not assign the next bidder.
bool canOfferToNextBidder(ListingSnapshot listing) => false;

/// Seller may open the edit form only while the listing is in the Active tab.
bool canEditListing(ListingSnapshot listing) =>
    listingBucketFor(listing) == ListingBucket.active;
