const int kSellerMaxActiveListings = 10;

const String kListingLimitReachedTitle = 'Listing limit reached';

const String kListingLimitReachedMessage =
    'You can have up to 10 active listings at a time. Mark an existing listing '
    'as inactive, sell an item, or remove a listing before posting another.';

const String kListingLimitReachedCode = 'listing_limit_reached';

bool sellerCanPublishListing(int activeCount) =>
    activeCount < kSellerMaxActiveListings;

/// Maps Supabase/Postgres errors from [assert_seller_active_listing_capacity].
String? listingLimitMessageFromError(Object error) {
  final text = error.toString();
  if (text.contains(kListingLimitReachedCode) ||
      text.contains('listing_limit_reached')) {
    return kListingLimitReachedMessage;
  }
  return null;
}
