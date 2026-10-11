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
