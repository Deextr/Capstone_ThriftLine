import '../../features/admin/data/admin_review_rules.dart';
import '../../features/auth/domain/legal_documents.dart';

abstract final class RouteNames {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String emailLogin = '/login/email';
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

  /// Opens the seller shell on a specific bottom-nav tab (`listings`, `orders`, …).
  static String sellerHomeWithTab(String tab) => '$sellerHome?tab=$tab';
  static const String search = '/search';
  static const String product = '/product/:id';

  /// Buyer catalog detail, or seller read-only preview when [ownerPreview].
  static String productFor(String productId, {bool ownerPreview = false}) {
    final id = productId.trim();
    if (ownerPreview) return '/product/$id?ownerPreview=1';
    return '/product/$id';
  }

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

  static const String myPurchases = '/my-purchases';
  static String myPurchasesTab(String queryValue) =>
      '$myPurchases?tab=$queryValue';
  static const String trackOrders = '/track-orders';
  static const String trackOrder = '/track-order/:orderId';
  static String trackOrderFor(String orderId) => '/track-order/$orderId';
  static const String orderDeliveryReport = '/orders/:orderId/report-problem';
  static String orderDeliveryReportFor(String orderId) =>
      '/orders/$orderId/report-problem';
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
  static const String followingShops = '/following-shops';
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
  static const String buyerToRate = '/buyer/to-rate';

  static String leaveReviewFor(String orderId) => '/leave-review/$orderId';

  static String buyerToRateTab({bool reviews = false}) =>
      reviews ? '$buyerToRate?tab=reviews' : buyerToRate;

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
  static const String sellerAnalytics = '/seller-analytics';
  /// Mobile-only: shown when an admin signs into the buyer/seller app.
  static const String adminPortalRequired = '/admin-portal-required';

  static const String adminLogin = '/admin/login';
  static const String adminVerifyEmailOtp = '/admin/verify-email-otp';
  static const String adminAccessDenied = '/admin/access-denied';
  static const String adminHome = '/admin';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminApplications = '/admin/applications';
  static const String adminVerifications = '/admin/verifications';
  static const String adminVerificationReview = '/admin/verifications/:id';
  static const String adminReview = '/admin/review/:id';
  static const String adminReports = '/admin/reports';
  static const String adminLogs = '/admin/logs';
  static const String adminReportsCommunity = '/admin/reports/community';
  static const String adminReportsOrders = '/admin/reports/orders';
  static const String adminReportsLookingFor = '/admin/reports/looking-for';
  static const String adminReportsQueue = '/admin/reports/queue/:kind';
  static const String adminReportDetail = '/admin/reports/:id';
  static const String adminDisputes = '/admin/disputes';
  static const String adminDisputeDetail = '/admin/disputes/:id';
  static const String adminLookingForReport = '/admin/looking-for-reports/:id';
  static const String adminDisabledAccounts = '/admin/disabled-accounts';
  static const String adminBidRiskEvents = '/admin/bid-risk-events';
  static const String adminUsers = '/admin/users';
  static const String adminOrders = '/admin/orders';
  static const String adminOrderDetail = '/admin/orders/:id';
  static const String adminTransactions = '/admin/transactions';
  static const String adminSettings = '/admin/settings';

  static String adminReviewFor(String id) => '/admin/verifications/$id';

  static String adminLegacyReviewFor(String id) => '/admin/review/$id';

  static String adminReportDetailFor(String id) => '/admin/reports/$id';

  static String adminReportsQueueFor(AdminReportKind kind) =>
      '/admin/reports/queue/${adminReportQueuePathSegment(kind)}';

  static String adminReportsCategoryFor(AdminReportKind kind) =>
      switch (kind) {
        AdminReportKind.community => adminReportsCommunity,
        AdminReportKind.order => adminReportsOrders,
        AdminReportKind.lookingFor => adminReportsLookingFor,
        AdminReportKind.all => adminReports,
      };

  static String adminDisputeDetailFor(String id) => '/admin/disputes/$id';

  static String adminLookingForReportFor(String id) =>
      '/admin/looking-for-reports/$id';

  static String adminOrderDetailFor(String id) => '/admin/orders/$id';
  static const String verifyPhone = '/verify-phone';

  static String verifyPhoneForBidReturn(String productId) =>
      '/verify-phone?returnBidProduct=$productId';
  static const String verifyEmailOtp = '/verify-email-otp';
  static const String addresses = '/addresses';
  static const String sellerShopAddress = '/seller/shop-address';
  static const String sellerMyRiders = '/seller/my-riders';
  static const String sellerSavedRiderEditor = '/seller/my-riders/editor';
  static const String paymentMethods = '/payment-methods';
}
