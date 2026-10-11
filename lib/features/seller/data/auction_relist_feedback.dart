import 'listing_snapshot.dart';

/// Seller-facing relist eligibility derived from listing snapshot state.
enum AuctionRelistBlockReason {
  notAuction,
  stillActive,
  awaitingPayment,
  finalizationPending,
  sold,
  eligible,
}

AuctionRelistBlockReason auctionRelistBlockReason(ListingSnapshot listing) {
  if (listing.listingType != 'auction') {
    return AuctionRelistBlockReason.notAuction;
  }

  if (listing.productStatus == 'sold' || listing.paymentStatus == 'paid') {
    return AuctionRelistBlockReason.sold;
  }

  final pastEnd =
      listing.endsAt != null && !listing.endsAt!.isAfter(listing.now);
  final stillLive =
      listing.auctionStatus == 'active' &&
      listing.endsAt != null &&
      listing.endsAt!.isAfter(listing.now);
  if (stillLive) {
    return AuctionRelistBlockReason.stillActive;
  }

  final winner = listing.winnerId != null && listing.winnerId!.isNotEmpty;
  final unpaid =
      listing.orderStatus == 'pending' && listing.paymentStatus != 'paid';
  final windowOpen =
      listing.paymentDueAt != null &&
      listing.paymentDueAt!.isAfter(listing.now);
  if (listing.auctionStatus == 'ended' && winner && unpaid && windowOpen) {
    return AuctionRelistBlockReason.awaitingPayment;
  }

  if (listing.auctionStatus == 'active' && pastEnd) {
    return AuctionRelistBlockReason.eligible;
  }

  if (listing.auctionStatus == 'cancelled') {
    return AuctionRelistBlockReason.eligible;
  }

  if (listing.auctionStatus != 'ended') {
    return AuctionRelistBlockReason.finalizationPending;
  }

  return AuctionRelistBlockReason.eligible;
}

bool canRelistAuction(ListingSnapshot listing) =>
    auctionRelistBlockReason(listing) == AuctionRelistBlockReason.eligible;

String? auctionRelistHint(ListingSnapshot listing) {
  return switch (auctionRelistBlockReason(listing)) {
    AuctionRelistBlockReason.stillActive =>
      'Auction still active: this auction has not ended yet.',
    AuctionRelistBlockReason.awaitingPayment =>
      'Awaiting winner payment: relisting is unavailable while the winning bidder\'s payment window is active.',
    AuctionRelistBlockReason.finalizationPending =>
      'Auction finalization pending: please try again once the previous auction has been finalized.',
    AuctionRelistBlockReason.sold =>
      'This item was sold and cannot be relisted as a new auction.',
    AuctionRelistBlockReason.eligible =>
      'Eligible for relisting: the previous auction has ended, and this item can be listed for bidding again.',
    AuctionRelistBlockReason.notAuction => null,
  };
}

String auctionRelistMessageFromRpc({String? code, String? error}) {
  if (error != null && error.trim().isNotEmpty) {
    return error.trim();
  }
  return switch (code) {
    'auction_still_active' =>
      'Auction still active: this auction has not ended yet.',
    'awaiting_winner_payment' =>
      'Awaiting winner payment: relisting is unavailable while the winning bidder\'s payment window is active.',
    'auction_finalization_pending' =>
      'Auction finalization pending: please try again once the previous auction has been finalized.',
    'auction_already_paid' =>
      'This auction was already paid and cannot be relisted.',
    'unresolved_dispute' =>
      'Relisting is unavailable while a delivery dispute for this auction is still open.',
    'listing_limit_reached' =>
      'You reached the active listing limit. Mark another listing inactive before relisting.',
    _ => 'Could not relist this auction.',
  };
}
