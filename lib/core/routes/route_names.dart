import '../../features/auth/domain/legal_documents.dart';

abstract final class RouteNames {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String legal = '/legal/:doc';

  /// Concrete path for the Terms and Conditions or Privacy Policy reader.
  static String legalDocument(LegalDocumentType type) => switch (type) {
    LegalDocumentType.terms => '/legal/terms',
    LegalDocumentType.privacy => '/legal/privacy',
  };

  static const String buyerHome = '/buyer';
  static const String sellerHome = '/seller';
  static const String search = '/search';
  static const String product = '/product/:id';
  static const String buyNow = '/buy-now/:id';
  static const String payment = '/payment/:id';
  static const String orderConfirm = '/order-confirm/:orderId';
  static const String paymentProof = '/payment-proof/:orderId';
  static const String trackOrder = '/track-order/:orderId';
  static const String addListing = '/add-listing';
  static const String editListing = '/edit-listing/:id';
  static const String sellerOrder = '/seller-order/:id';
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
  static const String checkout = '/checkout';
  static const String reportSeller = '/report-seller';
  static const String myReports = '/my-reports';
  static const String myShop = '/my-shop';
  static const String adminHome = '/admin';
  static const String adminReview = '/admin/review/:id';
  static const String verifyPhone = '/verify-phone';
  static const String verifyEmailOtp = '/verify-email-otp';
  static const String addresses = '/addresses';
}
