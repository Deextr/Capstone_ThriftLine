import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/data/mock_data.dart';
import '../models/bid_model.dart';
import '../models/chat_model.dart';
import '../models/enums.dart';
import '../models/looking_for_model.dart';
import '../models/message_model.dart';
import '../models/notification_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';

class DataProvider extends ChangeNotifier {
  DataProvider() {
    _products = List.from(MockData.products);
    _lookingFor = List.from(MockData.lookingForPosts);
    _userBids = List.from(MockData.mayaBids);
    _notifications = List.from(MockData.notifications);
    _chats = List.from(MockData.chats);
    _messages = List.from(MockData.messages);
    _orders = List.from(MockData.orders);
    _recentSearches = [
      'vintage denim jacket size M',
      'baggy 90s jeans size 29',
      'y2k butterfly top',
      'platform boots size 7',
      'korean blazer',
    ];
    _savedProductIds = {'prod_3', 'prod_8', 'prod_11'};
  }

  final _uuid = const Uuid();
  late List<ProductModel> _products;
  late List<LookingForModel> _lookingFor;
  late List<UserBid> _userBids;
  late List<NotificationModel> _notifications;
  late List<ChatModel> _chats;
  late List<MessageModel> _messages;
  late List<OrderModel> _orders;
  late List<String> _recentSearches;
  late Set<String> _savedProductIds;
  bool _notificationsEnabled = true;

  List<ProductModel> get products => _products;
  List<LookingForModel> get lookingForPosts => _lookingFor;
  List<String> get recentSearches => _recentSearches;
  List<String> get popularSearches => MockData.popularSearches;
  bool get notificationsEnabled => _notificationsEnabled;

  List<ProductModel> get endingSoonBids => _products
      .where((p) => p.hasActiveBid)
      .toList()
    ..sort((a, b) => (a.bidEndTime ?? DateTime.now())
        .compareTo(b.bidEndTime ?? DateTime.now()));

  List<ProductModel> get trendingProducts => _products.take(8).toList();

  int activeBidCountFor(String buyerId) => _userBids
      .where((b) =>
          b.buyerId == buyerId &&
          (b.status == BidStatus.active ||
              b.status == BidStatus.winning ||
              b.status == BidStatus.outbid))
      .length;

  List<UserBid> bidsForBuyer(String buyerId, BidTab tab) {
    final bids = _userBids.where((b) => b.buyerId == buyerId);
    switch (tab) {
      case BidTab.active:
        return bids.where((b) => b.status == BidStatus.winning || b.status == BidStatus.outbid || b.status == BidStatus.active).toList();
      case BidTab.won:
        return bids.where((b) => b.status == BidStatus.won).toList();
      case BidTab.lost:
        return bids.where((b) => b.status == BidStatus.lost).toList();
    }
  }

  ProductModel? productById(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  bool isSaved(String productId) => _savedProductIds.contains(productId);

  void toggleSave(String productId) {
    if (_savedProductIds.contains(productId)) {
      _savedProductIds.remove(productId);
    } else {
      _savedProductIds.add(productId);
    }
    notifyListeners();
  }

  int get savedCount => _savedProductIds.length;

  List<ProductModel> get savedProducts =>
      _products.where((p) => _savedProductIds.contains(p.id)).toList();

  List<ProductModel> searchProducts(String query, {String? category, String sort = 'Relevance'}) {
    var results = _products.where((p) => p.status == ProductStatus.active).toList();
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      results = results.where((p) =>
          p.title.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          p.category.label.toLowerCase().contains(q) ||
          (p.size?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (category != null && category != 'All') {
      results = results.where((p) => p.category.label == category).toList();
    }
    switch (sort) {
      case 'Price Low-High':
        results.sort((a, b) => a.displayPrice.compareTo(b.displayPrice));
      case 'Price High-Low':
        results.sort((a, b) => b.displayPrice.compareTo(a.displayPrice));
      case 'Newest':
        results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'Ending Soon':
        results.sort((a, b) {
          if (!a.hasActiveBid && !b.hasActiveBid) return 0;
          if (!a.hasActiveBid) return 1;
          if (!b.hasActiveBid) return -1;
          return (a.bidEndTime ?? DateTime.now()).compareTo(b.bidEndTime ?? DateTime.now());
        });
    }
    return results;
  }

  void addRecentSearch(String query) {
    if (query.trim().isEmpty) return;
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 5) _recentSearches = _recentSearches.take(5).toList();
    notifyListeners();
  }

  void removeRecentSearch(String query) {
    _recentSearches.remove(query);
    notifyListeners();
  }

  Future<bool> placeBid({
    required String productId,
    required String buyerId,
    required double amount,
  }) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return false;
    final product = _products[index];
    final minBid = (product.currentBid ?? product.startingBid ?? product.price) + product.bidIncrement;
    if (amount < minBid) return false;

    final newHistory = [
      BidEntry(
        id: _uuid.v4(),
        username: 'user***${buyerId.hashCode.abs() % 100}',
        amount: amount,
        createdAt: DateTime.now(),
      ),
      ...product.bidHistory,
    ];

    _products[index] = product.copyWith(
      currentBid: amount,
      bidCount: product.bidCount + 1,
      bidHistory: newHistory,
    );

    final bidIndex = _userBids.indexWhere((b) => b.productId == productId && b.buyerId == buyerId);
    if (bidIndex >= 0) {
      _userBids[bidIndex] = _userBids[bidIndex].copyWith(
        amount: amount,
        status: BidStatus.winning,
      );
    } else {
      _userBids.add(UserBid(
        id: _uuid.v4(),
        productId: productId,
        buyerId: buyerId,
        amount: amount,
        status: BidStatus.winning,
        createdAt: DateTime.now(),
      ));
    }

    for (var i = 0; i < _userBids.length; i++) {
      if (_userBids[i].productId == productId && _userBids[i].buyerId != buyerId) {
        _userBids[i] = _userBids[i].copyWith(status: BidStatus.outbid);
      }
    }

    notifyListeners();
    return true;
  }

  void addLookingFor(LookingForModel post) {
    _lookingFor.insert(0, post);
    notifyListeners();
  }

  OrderModel createOrder({
    required ProductModel product,
    required String buyerId,
    required String buyerName,
    required String buyerAvatar,
    required int quantity,
    required DeliveryMethod delivery,
    required PaymentMethod payment,
    required String address,
    String? size,
  }) {
    final subtotal = product.price * quantity;
    final shipping = delivery.fee;
    final platform = subtotal * 0.02;
    final total = subtotal + shipping + platform;
    final order = OrderModel(
      id: _uuid.v4(),
      orderNumber: 'TL-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
      productId: product.id,
      buyerId: buyerId,
      sellerId: _sellerIdFor(product.sellerUsername),
      productTitle: product.title,
      productImage: product.imageUrl,
      sellerName: product.sellerName,
      buyerName: buyerName,
      buyerAvatar: buyerAvatar,
      amount: subtotal,
      shippingFee: shipping,
      platformFee: platform,
      total: total,
      status: payment == PaymentMethod.cod ? OrderStatus.placed : OrderStatus.paymentPending,
      paymentMethod: payment,
      deliveryMethod: delivery,
      shippingAddress: address,
      createdAt: DateTime.now(),
      quantity: quantity,
      size: size ?? product.size,
      estimatedDelivery: DateTime.now().add(
        Duration(days: delivery == DeliveryMethod.express ? 2 : 5),
      ),
    );
    _orders.insert(0, order);
    notifyListeners();
    return order;
  }

  String _sellerIdFor(String username) {
    switch (username) {
      case 'vintagevibes_ph':
        return 'seller_carla';
      case 'thrift_trendy':
        return 'seller_rico';
      case 'preloved_gems':
        return 'seller_anna';
      default:
        return 'seller_carla';
    }
  }

  List<OrderModel> ordersForBuyer(String buyerId) =>
      _orders.where((o) => o.buyerId == buyerId).toList();

  List<OrderModel> ordersForSeller(String sellerId) =>
      _orders.where((o) => o.sellerId == sellerId).toList();

  OrderModel? orderById(String id) {
    try {
      return _orders.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  void updateOrderStatus(String orderId, OrderStatus status, {String? tracking}) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return;
    _orders[index] = _orders[index].copyWith(
      status: status,
      trackingNumber: tracking ?? _orders[index].trackingNumber,
      courier: tracking != null ? 'J&T Express' : _orders[index].courier,
    );
    notifyListeners();
  }

  void submitPaymentProof(String orderId) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return;
    _orders[index] = _orders[index].copyWith(
      paymentProofSubmitted: true,
      status: OrderStatus.paymentConfirmed,
    );
    notifyListeners();
  }

  List<NotificationModel> notificationsFor(String userId) =>
      _notifications.where((n) => n.userId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void markNotificationRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _notifications[index] = _notifications[index].copyWith(isRead: true);
    notifyListeners();
  }

  void markAllNotificationsRead(String userId) {
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].userId == userId) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
  }

  int unreadNotificationCount(String userId) =>
      _notifications.where((n) => n.userId == userId && !n.isRead).length;

  List<ChatModel> chatsFor(String userId) =>
      _chats.where((c) => c.participantIds.contains(userId)).toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

  List<MessageModel> messagesFor(String chatId) =>
      _messages.where((m) => m.chatId == chatId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    MessageType type = MessageType.text,
    double? offerAmount,
  }) {
    _messages.add(MessageModel(
      id: _uuid.v4(),
      chatId: chatId,
      senderId: senderId,
      content: content,
      createdAt: DateTime.now(),
      type: type,
      offerAmount: offerAmount,
    ));
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex >= 0) {
      final chat = _chats[chatIndex];
      _chats[chatIndex] = ChatModel(
        id: chat.id,
        participantIds: chat.participantIds,
        participantNames: chat.participantNames,
        participantAvatars: chat.participantAvatars,
        productId: chat.productId,
        productTitle: chat.productTitle,
        productImage: chat.productImage,
        lastMessage: content,
        lastMessageAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  void toggleNotifications() {
    _notificationsEnabled = !_notificationsEnabled;
    notifyListeners();
  }

  int pendingOrdersForSeller(String sellerId) =>
      _orders.where((o) =>
          o.sellerId == sellerId &&
          (o.status == OrderStatus.placed ||
              o.status == OrderStatus.paymentPending ||
              o.status == OrderStatus.paymentConfirmed)).length;

  List<ProductModel> productsForSeller(String username) =>
      _products.where((p) => p.sellerUsername == username).toList();

  void addProduct(ProductModel product) {
    _products.insert(0, product);
    notifyListeners();
  }
}
