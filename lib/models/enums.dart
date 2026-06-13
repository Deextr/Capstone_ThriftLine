enum UserRole {
  buyer,
  seller;

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
  fair('Fair');

  const ProductCondition(this.label);
  final String label;

  static ProductCondition fromString(String value) {
    for (final c in ProductCondition.values) {
      if (c.name == value) return c;
    }
    return ProductCondition.good;
  }
}

enum ProductStatus {
  active,
  paused,
  sold,
  draft;

  static ProductStatus fromString(String value) => ProductStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ProductStatus.active,
      );
}

enum SellingType {
  fixedPrice,
  auction,
  both;

  static SellingType fromString(String value) => SellingType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => SellingType.fixedPrice,
      );
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
