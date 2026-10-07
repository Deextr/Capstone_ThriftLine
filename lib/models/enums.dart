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
  secondChance,
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
  completed,
  disputed,
  cancelled;

  static OrderStatus fromString(String value) => OrderStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => OrderStatus.placed,
  );
}

String orderStatusLabel(Object? status) {
  if (status is OrderStatus) {
    return switch (status) {
      OrderStatus.paymentPending || OrderStatus.placed => 'Awaiting payment',
      OrderStatus.paymentConfirmed || OrderStatus.preparing => 'Paid / To ship',
      OrderStatus.shipped => 'Shipped',
      OrderStatus.outForDelivery => 'Out for delivery',
      OrderStatus.delivered => 'Inspecting',
      OrderStatus.completed => 'Completed',
      OrderStatus.disputed => 'Disputed',
      OrderStatus.cancelled => 'Cancelled',
    };
  }
  if (status is String) return status;
  return 'unknown';
}

OrderStatus orderStatusFromDb(String? value) => switch (value) {
  'pending' || 'payment_pending' || 'placed' => OrderStatus.paymentPending,
  'to_ship' ||
  'preparing' ||
  'payment_confirmed' ||
  'paid' => OrderStatus.preparing,
  'shipped' => OrderStatus.shipped,
  'out_for_delivery' => OrderStatus.outForDelivery,
  'delivered' => OrderStatus.delivered,
  'completed' => OrderStatus.completed,
  'disputed' => OrderStatus.disputed,
  'cancelled' => OrderStatus.cancelled,
  _ => OrderStatus.paymentPending,
};

enum DeliveryStatus {
  sellerPreparing('seller_preparing', 'Seller preparing'),
  riderAssigned('rider_assigned', 'Rider assigned'),
  readyForPickup('ready_for_pickup', 'Ready for pickup'),
  pickedUp('picked_up', 'Parcel picked up'),
  outForDelivery('out_for_delivery', 'Out for delivery'),
  awaitingDeliveryVerification(
    'awaiting_delivery_verification',
    'Awaiting verification',
  ),
  deliveryVerified('delivery_verified', 'Delivery verified'),
  inspectionPeriod('inspection_period', 'Inspection period'),
  deliveryFailed('delivery_failed', 'Delivery failed'),
  disputed('disputed', 'Disputed'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const DeliveryStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DeliveryStatus fromDb(String? value) => switch (value) {
    'seller_preparing' => DeliveryStatus.sellerPreparing,
    'rider_assigned' => DeliveryStatus.riderAssigned,
    'ready_for_pickup' => DeliveryStatus.readyForPickup,
    'picked_up' => DeliveryStatus.pickedUp,
    'out_for_delivery' => DeliveryStatus.outForDelivery,
    'awaiting_delivery_verification' =>
      DeliveryStatus.awaitingDeliveryVerification,
    'delivery_verified' => DeliveryStatus.deliveryVerified,
    'inspection_period' => DeliveryStatus.inspectionPeriod,
    'delivery_failed' => DeliveryStatus.deliveryFailed,
    'disputed' => DeliveryStatus.disputed,
    'completed' => DeliveryStatus.completed,
    'cancelled' => DeliveryStatus.cancelled,
    _ => DeliveryStatus.sellerPreparing,
  };

  bool get isPreparing =>
      this == DeliveryStatus.sellerPreparing ||
      this == DeliveryStatus.riderAssigned ||
      this == DeliveryStatus.readyForPickup;

  bool get isInTransit =>
      this == DeliveryStatus.pickedUp ||
      this == DeliveryStatus.outForDelivery ||
      this == DeliveryStatus.awaitingDeliveryVerification;

  /// Rider identity may be edited only before the parcel is out for delivery.
  bool get allowsRiderUpdates =>
      this == DeliveryStatus.sellerPreparing ||
      this == DeliveryStatus.riderAssigned ||
      this == DeliveryStatus.readyForPickup ||
      this == DeliveryStatus.pickedUp;

  bool get isInspecting =>
      this == DeliveryStatus.deliveryVerified ||
      this == DeliveryStatus.inspectionPeriod;
}

enum DeliveryVehicleType {
  motorcycle('motorcycle', 'Motorcycle'),
  car('car', 'Car'),
  van('van', 'Van'),
  bicycle('bicycle', 'Bicycle'),
  other('other', 'Other');

  const DeliveryVehicleType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  bool get requiresPlate =>
      this == motorcycle || this == car || this == van;

  static DeliveryVehicleType fromDb(String? value) =>
      DeliveryVehicleType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => DeliveryVehicleType.motorcycle,
      );
}

enum DeliveryFailureReason {
  buyerUnavailable('buyer_unavailable', 'Buyer unavailable'),
  buyerRefusedDelivery('buyer_refused_delivery', 'Buyer refused delivery'),
  buyerRefusedVerification(
    'buyer_refused_verification',
    'Buyer refused verification',
  ),
  unableToContactBuyer('unable_to_contact_buyer', 'Unable to contact buyer'),
  incorrectAddress('incorrect_address', 'Incorrect address'),
  other('other', 'Other');

  const DeliveryFailureReason(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DeliveryFailureReason? fromDb(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final reason in DeliveryFailureReason.values) {
      if (reason.dbValue == value) return reason;
    }
    return DeliveryFailureReason.other;
  }
}

enum DeliveryDisputeReason {
  parcelNotReceived('parcel_not_received', 'Parcel not received'),
  wrongItem('wrong_item', 'Wrong item'),
  damagedItem('damaged_item', 'Damaged item'),
  significantlyDifferent(
    'significantly_different',
    'Item significantly different from listing',
  ),
  missingItem('missing_item', 'Missing item'),
  missingQuantity('missing_quantity', 'Missing quantity'),
  emptyParcel('empty_parcel', 'Empty parcel'),
  other('other', 'Other');

  const DeliveryDisputeReason(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DeliveryDisputeReason fromDb(String? value) {
    if (value == null || value.isEmpty) return DeliveryDisputeReason.other;
    for (final reason in DeliveryDisputeReason.values) {
      if (reason.dbValue == value) return reason;
    }
    return DeliveryDisputeReason.other;
  }
}

enum PaymentMethod {
  unpaid('Payment pending'),
  paymongo('GCash'),
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
  offer,
  lookingFor;

  String get dbValue => switch (this) {
    MessageType.lookingFor => 'looking_for',
    _ => name,
  };

  static MessageType fromString(String value) => switch (value) {
    'looking_for' || 'lookingFor' => MessageType.lookingFor,
    'image' => MessageType.image,
    'offer' => MessageType.offer,
    _ => MessageType.text,
  };
}

enum NotificationAudience {
  buyer,
  seller,
  system;

  static NotificationAudience fromString(String? value) => switch (value) {
    'buyer' => NotificationAudience.buyer,
    'seller' => NotificationAudience.seller,
    'system' => NotificationAudience.system,
    _ => NotificationAudience.system,
  };

  String get dbValue => name;
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
  review,
  reportDecision,
  system;

  static NotificationType fromString(String value) => switch (value) {
    'report_decision' => NotificationType.reportDecision,
    'review' => NotificationType.review,
    _ => NotificationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationType.system,
    ),
  };
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
