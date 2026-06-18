import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/buyer/presentation/screens/become_seller_screen.dart';
import '../../features/buyer/presentation/screens/buyer_shell_screen.dart';
import '../../features/buyer/presentation/screens/buy_now_screen.dart';
import '../../features/buyer/presentation/screens/edit_profile_screen.dart';
import '../../features/buyer/presentation/screens/order_confirmation_screen.dart';
import '../../features/buyer/presentation/screens/order_tracking_screen.dart';
import '../../features/buyer/presentation/screens/payment_delivery_screen.dart';
import '../../features/buyer/presentation/screens/payment_proof_screen.dart';
import '../../features/buyer/presentation/screens/product_detail_screen.dart';
import '../../features/buyer/presentation/screens/purchase_history_screen.dart';
import '../../features/buyer/presentation/screens/saved_items_screen.dart';
import '../../features/buyer/presentation/screens/search_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../../features/chat/presentation/screens/chat_list_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/seller/presentation/screens/add_listing_screen.dart';
import '../../features/seller/presentation/screens/seller_order_detail_screen.dart';
import '../../features/seller/presentation/screens/seller_shell_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
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

      if (isSplash) return null;

      if (!appProvider.isOnboardingComplete && !isOnboarding) {
        return RouteNames.onboarding;
      }

      if (!authProvider.isAuthenticated && !isLogin && !isSignup && !isOnboarding) {
        return RouteNames.login;
      }

      if (authProvider.isAuthenticated) {
        if (isLogin || isSignup || isOnboarding) return authProvider.homeRoute;
        if (authProvider.isSeller && location == RouteNames.buyerHome) {
          return RouteNames.sellerHome;
        }
        if (authProvider.isBuyer && location == RouteNames.sellerHome) {
          return RouteNames.buyerHome;
        }
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
        path: RouteNames.buyerHome,
        builder: (_, _) => const BuyerShellScreen(),
      ),
      GoRoute(
        path: RouteNames.sellerHome,
        builder: (_, _) => const SellerShellScreen(),
      ),
      GoRoute(path: RouteNames.search, builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: RouteNames.product,
        builder: (_, state) =>
            ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RouteNames.buyNow,
        builder: (_, state) =>
            BuyNowScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RouteNames.payment,
        builder: (_, state) =>
            PaymentDeliveryScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RouteNames.orderConfirm,
        builder: (_, state) =>
            OrderConfirmationScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: RouteNames.paymentProof,
        builder: (_, state) =>
            PaymentProofScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: RouteNames.trackOrder,
        builder: (_, state) =>
            OrderTrackingScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: RouteNames.addListing,
        builder: (_, _) => const AddListingScreen(),
      ),
      GoRoute(
        path: RouteNames.sellerOrder,
        builder: (_, state) =>
            SellerOrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: RouteNames.chat, builder: (_, _) => const ChatListScreen()),
      GoRoute(
        path: RouteNames.chatDetail,
        builder: (_, state) =>
            ChatDetailScreen(chatId: state.pathParameters['id']!),
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
        builder: (_, _) => const PurchaseHistoryScreen(),
      ),
      GoRoute(
        path: RouteNames.savedItems,
        builder: (_, _) => const SavedItemsScreen(),
      ),
      GoRoute(
        path: RouteNames.becomeSeller,
        builder: (_, _) => const BecomeSellerScreen(),
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
