import '../../features/auth/domain/legal_documents.dart';

abstract final class RouteNames {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String legal = '/legal/:doc';

  /// Concrete path for the Terms and Conditions, Privacy Policy, About, or FAQ reader.
  static String legalDocument(LegalDocumentType type) => switch (type) {
    LegalDocumentType.terms => '/legal/terms',
    LegalDocumentType.privacy => '/legal/privacy',
    LegalDocumentType.about => '/legal/about',
    LegalDocumentType.faq => '/legal/faq',
  };

  static const String buyerHome = '/buyer';
  static const String sellerHome = '/seller';
  static const String search = '/search';
  static const String product = '/product/:id';
  static const String buyNow = '/buy-now/:id';
  static const String payment = '/payment/:id';
  static const String orderConfirm = '/order-confirm/:orderId';
  static const String paymentProof = '/payment-proof/:orderId';

  static String orderConfirmFor(String orderId) => '/order-confirm/$orderId';

  static String paymentForOrder(String orderId, {bool autostart = false}) =>
      '/payment-proof/$orderId${autostart ? '?autostart=1' : ''}';

  static String paymentReturnFor(
    String orderId, {
    bool cancelled = false,
    bool expired = false,
  }) {
    final status = expired
        ? 'expired'
        : cancelled
        ? 'cancel'
        : 'success';
    return '/payment-proof/$orderId?returned=1&status=$status';
  }

  static const String trackOrders = '/track-orders';
  static const String trackOrder = '/track-order/:orderId';
  static String trackOrderFor(String orderId) => '/track-order/$orderId';
  static const String addListing = '/add-listing';
  static const String editListing = '/edit-listing/:id';
  static const String sellerOrder = '/seller-order/:id';
  static const String arrangeDelivery = '/seller-order/:id/arrange-delivery';
  static const String arrangeReturn = '/seller-order/:id/arrange-return';
  static String arrangeDeliveryFor(String id) =>
      '/seller-order/$id/arrange-delivery';
  static String arrangeReturnFor(String id) =>
      '/seller-order/$id/arrange-return';
  static const String chat = '/chat';
  static const String chatDetail = '/chat/:id';
  static String chatThread(String id) => '/chat/$id';
  static const String lookingFor = '/looking-for/:id';
  static String lookingForPost(String id) => '/looking-for/$id';
  static const String notifications = '/notifications';
  static const String editProfile = '/edit-profile';
  static const String settings = '/settings';
  static const String purchaseHistory = '/purchase-history';
  static const String savedItems = '/saved-items';
  static const String becomeSeller = '/become-seller';
  static const String sellerProfile = '/seller-profile/:username';
  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String homeEndingSoon = '/discover/ending-soon';
  static const String homeSuggested = '/discover/suggested';
  static const String homeBidding = '/discover/bidding';
  static const String homeVerifiedSellers = '/discover/verified-sellers';

  /// Opens checkout for one Buy Now product, or for the cart lines selected.
  static String checkoutFor({
    String? productId,
    List<String> productIds = const [],
  }) {
    final single = productId?.trim();
    if (single != null && single.isNotEmpty) {
      return '$checkout?product=$single';
    }
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.length == 1) return '$checkout?product=${ids.first}';
    if (ids.length > 1) return '$checkout?products=${ids.join(',')}';
    return checkout;
  }

  static const String reportSeller = '/report-seller';
  static const String myReports = '/my-reports';
  static const String reportDetail = '/my-reports/:id';
  static const String accountReview = '/account-review/:reportId';
  static const String leaveReview = '/leave-review/:orderId';

  static String leaveReviewFor(String orderId) => '/leave-review/$orderId';

  static String reportDetailFor(String id) => '/my-reports/$id';

  static String accountReviewFor(String reportId) =>
      '/account-review/$reportId';

  static String reportUser({
    String? username,
    String? userId,
    String? orderId,
  }) {
    return Uri(
      path: reportSeller,
      queryParameters: {
        if (username != null && username.isNotEmpty) 'seller': username,
        if (userId != null && userId.isNotEmpty) 'user': userId,
        if (orderId != null && orderId.isNotEmpty) 'order': orderId,
      },
    ).toString();
  }

  static const String myShop = '/my-shop';
  static const String adminHome = '/admin';
  static const String adminApplications = '/admin/applications';
  static const String adminReview = '/admin/review/:id';
  static const String adminReports = '/admin/reports';
  static const String adminReportDetail = '/admin/reports/:id';
  static const String adminDisputes = '/admin/disputes';
  static const String adminDisputeDetail = '/admin/disputes/:id';

  static String adminReviewFor(String id) => '/admin/review/$id';
  static String adminReportDetailFor(String id) => '/admin/reports/$id';
  static String adminDisputeDetailFor(String id) => '/admin/disputes/$id';
  static const String verifyPhone = '/verify-phone';
  static const String verifyEmailOtp = '/verify-email-otp';
  static const String addresses = '/addresses';
  static const String paymentMethods = '/payment-methods';
}
