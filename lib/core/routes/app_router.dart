import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/domain/legal_documents.dart';
import '../../features/auth/presentation/screens/legal_document_screen.dart';
import '../../features/admin/presentation/screens/admin_review_screen.dart';
import '../../features/admin/presentation/screens/admin_shell_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/verify_email_otp_screen.dart';
import '../../features/auth/presentation/screens/verify_phone_screen.dart';
import '../../features/profile/presentation/screens/address_book_screen.dart';
import '../../features/buyer/presentation/screens/become_seller_screen.dart';
import '../../features/buyer/presentation/screens/buyer_shell_screen.dart';
import '../../features/buyer/presentation/screens/buy_now_screen.dart';
import '../../features/buyer/presentation/screens/checkout_screen.dart';
import '../../features/profile/controllers/seller_public_profile_controller.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/seller_public_profile_screen.dart';
import '../../features/buyer/presentation/screens/order_confirmation_screen.dart';
import '../../features/buyer/presentation/screens/order_tracking_screen.dart';
import '../../features/buyer/presentation/screens/payment_proof_screen.dart';
import '../../features/buyer/controllers/buyer_orders_controller.dart';
import '../../features/buyer/controllers/checkout_controller.dart';
import '../../features/buyer/controllers/product_detail_controller.dart';
import '../../features/buyer/controllers/buyer_search_controller.dart';
import '../../features/seller/controllers/my_shop_controller.dart';
import '../../features/seller/controllers/seller_orders_controller.dart';
import '../../providers/cart_provider.dart';
import '../../features/buyer/presentation/screens/product_detail_screen.dart';
import '../../features/buyer/presentation/screens/purchase_history_screen.dart';
import '../../features/buyer/presentation/screens/saved_items_screen.dart';
import '../../features/buyer/presentation/screens/buyer_search_tab.dart';
import '../../features/chat/controllers/chat_detail_controller.dart';
import '../../features/chat/controllers/chat_list_controller.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../../features/chat/presentation/screens/chat_list_screen.dart';
import '../../features/buyer/controllers/looking_for_detail_controller.dart';
import '../../features/buyer/presentation/screens/looking_for_detail_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/seller/controllers/add_listing_controller.dart';
import '../../features/seller/controllers/edit_listing_controller.dart';
import '../../features/seller/presentation/screens/add_listing_screen.dart';
import '../../features/seller/presentation/screens/edit_listing_screen.dart';
import '../services/shared_preferences_service.dart';
import '../services/supabase_service.dart';
import '../../features/seller/presentation/screens/seller_order_detail_screen.dart';
import '../../features/seller/presentation/screens/seller_shell_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/seller/presentation/screens/my_shop_screen.dart';
import '../../features/trust_safety/presentation/screens/report_seller_screen.dart';
import '../../features/trust_safety/presentation/screens/my_reports_screen.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import 'auth_redirect.dart';
import 'route_names.dart';

GoRouter createAppRouter({
  required AuthProvider authProvider,
  required AppProvider appProvider,
}) {
  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: Listenable.merge([authProvider, appProvider]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isSplash = location == RouteNames.splash;
      final isOnboarding = location == RouteNames.onboarding;
      final isLogin = location == RouteNames.login;
      final isSignup = location == RouteNames.signup;
      final isLegal = location.startsWith('/legal/');
      final isVerifyEmailOtp = location == RouteNames.verifyEmailOtp;

      if (isSplash) return null;

      // The legal documents must stay reachable at every stage, including
      // while the user is deciding whether to consent.
      if (isLegal) return null;

      if (!appProvider.isOnboardingComplete && !isOnboarding) {
        return RouteNames.onboarding;
      }

      if (authProvider.isEmailOtpPending) {
        if (!authProvider.isAuthenticated) {
          return unauthenticatedEmailOtpRedirect(
            location: location,
            isAuthenticated: false,
            emailOtpPending: true,
          );
        }
        if (!isVerifyEmailOtp) return RouteNames.verifyEmailOtp;
        return null;
      }

      if (!authProvider.isFullyAuthenticated &&
          !isLogin &&
          !isSignup &&
          !isOnboarding) {
        return RouteNames.login;
      }

      if (authProvider.isFullyAuthenticated) {
        if (isLogin || isSignup || isOnboarding || isVerifyEmailOtp) {
          return authProvider.homeRoute;
        }
        return authenticatedWorkspaceRedirect(
          isAdmin: authProvider.isAdmin,
          isSellerMode: authProvider.isSeller,
          isBuyerMode: authProvider.isBuyer,
          location: location,
          homeRoute: authProvider.homeRoute,
        );
      }
      return null;
    },
    routes: [
      GoRoute(path: RouteNames.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(path: RouteNames.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: RouteNames.signup, builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: RouteNames.verifyEmailOtp,
        builder: (_, _) => const VerifyEmailOtpScreen(),
      ),
      GoRoute(
        path: RouteNames.legal,
        builder: (_, state) => LegalDocumentScreen(
          type: state.pathParameters['doc'] == 'privacy'
              ? LegalDocumentType.privacy
              : LegalDocumentType.terms,
        ),
      ),
      GoRoute(
        path: RouteNames.buyerHome,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => BuyerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const BuyerShellScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.sellerHome,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => SellerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const SellerShellScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.search,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => BuyerSearchController(
            supabase: context.read<SupabaseService>(),
            prefs: context.read<SharedPreferencesService>(),
            userId: context.read<AuthProvider>().user?.id,
          ),
          child: const SearchScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.product,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => ProductDetailController(
            productId: state.pathParameters['id']!,
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: ProductDetailScreen(productId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: RouteNames.buyNow,
        builder: (_, state) =>
            BuyNowScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RouteNames.payment,
        redirect: (_, state) {
          final id = state.pathParameters['id'];
          if (id == null || id.isEmpty) return RouteNames.checkout;
          return '${RouteNames.checkout}?product=$id';
        },
      ),
      GoRoute(
        path: RouteNames.orderConfirm,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => BuyerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
            orderId: state.pathParameters['orderId'],
          ),
          child: OrderConfirmationScreen(
            orderId: state.pathParameters['orderId']!,
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.paymentProof,
        builder: (_, state) =>
            PaymentProofScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: RouteNames.trackOrder,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => BuyerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
            orderId: state.pathParameters['orderId'],
          ),
          child: OrderTrackingScreen(orderId: state.pathParameters['orderId']!),
        ),
      ),
      GoRoute(
        path: RouteNames.addListing,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => AddListingController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const AddListingScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.editListing,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => EditListingController(
            productId: state.pathParameters['id']!,
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const EditListingScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.sellerOrder,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => SellerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
            orderId: state.pathParameters['id'],
          ),
          child: SellerOrderDetailScreen(orderId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: RouteNames.chat,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => ChatListController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const ChatListScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.chatDetail,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => ChatDetailController(
            conversationId: state.pathParameters['id']!,
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: ChatDetailScreen(chatId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: RouteNames.lookingFor,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => LookingForDetailController(
            postId: state.pathParameters['id']!,
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const LookingForDetailScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RouteNames.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: RouteNames.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: RouteNames.purchaseHistory,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => BuyerOrdersController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const PurchaseHistoryScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.savedItems,
        builder: (_, _) => const SavedItemsScreen(),
      ),
      GoRoute(
        path: RouteNames.becomeSeller,
        builder: (_, _) => const BecomeSellerScreen(),
      ),
      GoRoute(
        path: RouteNames.sellerProfile,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => SellerPublicProfileController(
            username: state.pathParameters['username']!,
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: SellerPublicProfileScreen(
            username: state.pathParameters['username']!,
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.checkout,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => CheckoutController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
            cart: context.read<CartProvider>(),
            buyNowProductId: state.uri.queryParameters['product'],
          ),
          child: const CheckoutScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.reportSeller,
        builder: (_, state) => ReportSellerScreen(
          sellerUsername: state.uri.queryParameters['seller'],
        ),
      ),
      GoRoute(
        path: RouteNames.myReports,
        builder: (_, _) => const MyReportsScreen(),
      ),
      GoRoute(
        path: RouteNames.myShop,
        builder: (context, _) => ChangeNotifierProvider(
          create: (context) => MyShopController(
            supabase: context.read<SupabaseService>(),
            auth: context.read<AuthProvider>(),
          ),
          child: const MyShopScreen(),
        ),
      ),
      GoRoute(
        path: RouteNames.adminHome,
        builder: (_, _) => const AdminShellScreen(),
      ),
      GoRoute(
        path: RouteNames.adminReview,
        builder: (_, state) =>
            AdminReviewScreen(verificationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RouteNames.verifyPhone,
        builder: (_, _) => const VerifyPhoneScreen(),
      ),
      GoRoute(
        path: RouteNames.addresses,
        builder: (_, _) => const AddressBookScreen(),
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
