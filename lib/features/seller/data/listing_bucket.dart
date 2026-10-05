/// Display buckets for My Listings. These do not add a product status.
enum ListingBucket { active, awaitingPayment, sold, inactive }

class ListingSnapshot {
  const ListingSnapshot({
    required this.productStatus,
    required this.listingType,
    this.auctionStatus,
    this.endsAt,
    this.winnerId,
    this.orderStatus,
    this.paymentStatus,
    this.paymentDueAt,
    this.bidCount = 0,
    required this.now,
  });

  final String productStatus;
  final String listingType;
  final String? auctionStatus;
  final DateTime? endsAt;
  final String? winnerId;
  final String? orderStatus;
  final String? paymentStatus;
  final DateTime? paymentDueAt;
  final int bidCount;
  final DateTime now;
}

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

bool canRelistAuction(ListingSnapshot listing) {
  return listing.listingType == 'auction' &&
      listingBucketFor(listing) == ListingBucket.inactive;
}

/// Fallback to the second-highest bidder is automatic after the primary
/// winner's payment window expires. Sellers do not assign the next bidder.
bool canOfferToNextBidder(ListingSnapshot listing) => false;

/// Seller may open the edit form only while the listing is in the Active tab.
bool canEditListing(ListingSnapshot listing) =>
    listingBucketFor(listing) == ListingBucket.active;
