enum UserRole {
  buyer,
  seller,
  admin;

  static UserRole fromString(String value) => UserRole.values.firstWhere(
    (e) => e.name == value,
    orElse: () => UserRole.buyer,
  );
}

enum ProductCategory {
  tops('Tops'),
  bottoms('Bottoms'),
  dresses('Dresses'),
  outerwear('Outerwear'),
  shoes('Shoes'),
  bags('Bags'),
  accessories('Accessories'),
  vintage('Vintage'),
  streetwear('Streetwear'),
  formal('Formal');

  const ProductCategory(this.label);
  final String label;

  static ProductCategory fromString(String value) {
    for (final c in ProductCategory.values) {
      if (c.name == value || c.label.toLowerCase() == value.toLowerCase()) {
        return c;
      }
    }
    return ProductCategory.tops;
  }
}

enum ProductCondition {
  newWithTags('New with tags'),
  likeNew('Like new'),
  good('Good'),
  fair('Fair'),
  poor('Poor');

  const ProductCondition(this.label);
  final String label;

  static ProductCondition fromString(String value) {
    for (final c in ProductCondition.values) {
      if (c.name == value) return c;
    }
    return ProductCondition.good;
  }

  /// Parses the Supabase `product_condition_enum` value.
  static ProductCondition fromDbString(String value) => switch (value) {
    'new' => ProductCondition.newWithTags,
    'like_new' => ProductCondition.likeNew,
    'good' => ProductCondition.good,
    'fair' => ProductCondition.fair,
    'poor' => ProductCondition.poor,
    _ => ProductCondition.good,
  };
}

/// Mirrors `product_status_enum` in Postgres.
enum ProductStatus {
  active,
  sold,
  removed,
  draft;

  static ProductStatus fromString(String value) => ProductStatus.values
      .firstWhere((e) => e.name == value, orElse: () => ProductStatus.active);

  /// Parses the Supabase `product_status_enum` value.
  static ProductStatus fromDbString(String value) => switch (value) {
    'active' => ProductStatus.active,
    'sold' => ProductStatus.sold,
    'removed' => ProductStatus.removed,
    'draft' => ProductStatus.draft,
    _ => ProductStatus.active,
  };
}

enum SellingType {
  fixedPrice,
  auction,
  both,
  liveSession;

  static SellingType fromString(String value) => SellingType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => SellingType.fixedPrice,
  );

  /// Parses the Supabase `listing_type_enum` value.
  static SellingType fromDbString(String value) => switch (value) {
    'fixed_price' => SellingType.fixedPrice,
    'auction' => SellingType.auction,
    'live_session' => SellingType.liveSession,
    _ => SellingType.fixedPrice,
  };
}

enum BidStatus {
  active,
  winning,
  outbid,
  won,
  lost,
  expired;

  static BidStatus fromString(String value) => BidStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => BidStatus.active,
  );
}

enum OrderStatus {
  placed,
  paymentPending,
  paymentConfirmed,
  preparing,
  shipped,
  outForDelivery,
  delivered,
  cancelled;

  static OrderStatus fromString(String value) => OrderStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => OrderStatus.placed,
  );
}

String orderStatusLabel(Object? status) {
  if (status is OrderStatus) return status.name;
  if (status is String) return status;
  return 'unknown';
}

enum PaymentMethod {
  gcash('GCash'),
  maya('Maya'),
  bankTransfer('Bank Transfer'),
  cod('Cash on Delivery');

  const PaymentMethod(this.label);
  final String label;
}

enum DeliveryMethod {
  standard('Standard (3-5 days)', 80),
  express('Express (1-2 days)', 150),
  meetup('Meet-up', 0);

  const DeliveryMethod(this.label, this.fee);
  final String label;
  final double fee;
}

enum MessageType {
  text,
  image,
  offer;

  static MessageType fromString(String value) => MessageType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => MessageType.text,
  );
}

enum NotificationType {
  outbid,
  wonBid,
  shipped,
  message,
  saved,
  orderConfirmed,
  verificationSubmitted,
  verificationApproved,
  verificationRejected,
  system;

  static NotificationType fromString(String value) =>
      NotificationType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => NotificationType.system,
      );
}

enum LookingForStatus {
  active,
  fulfilled,
  closed;

  static LookingForStatus fromString(String value) =>
      LookingForStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LookingForStatus.active,
      );
}

enum ListingTab { active, sold, drafts }

enum OrderTab { pending, toShip, shipped, completed, cancelled }

enum BidTab { active, won, lost }
