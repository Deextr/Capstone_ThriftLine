import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/admin/controllers/admin_bid_risk_controller.dart';
import '../../features/admin/controllers/admin_bidding_violations_controller.dart';
import '../../features/admin/data/admin_bidding_violations_service.dart';
import '../../features/admin/controllers/admin_dashboard_controller.dart';
import '../../features/admin/controllers/admin_disabled_accounts_controller.dart';
import '../../features/admin/controllers/admin_analytics_controller.dart';
import '../../features/admin/controllers/admin_marketplace_reports_controller.dart';
import '../../features/admin/domain/marketplace_report_catalog.dart';
import '../../features/admin/presentation/web/admin_web_marketplace_reports_page.dart';
import '../../features/admin/controllers/admin_disputes_controller.dart';
import '../../features/admin/controllers/admin_disputes_hub_controller.dart';
import '../../features/admin/controllers/admin_looking_for_report_controller.dart';
import '../../features/admin/controllers/admin_orders_list_controller.dart';
import '../../features/admin/domain/admin_order_management.dart';
import '../../features/admin/domain/auction_bidding_violations.dart';
import '../../features/admin/controllers/admin_reports_controller.dart';
import '../../features/admin/controllers/admin_seller_applications_controller.dart';
import '../../features/admin/controllers/admin_users_controller.dart';
import '../../features/admin/data/admin_review_rules.dart';
import '../../features/admin/presentation/screens/admin_bid_risk_events_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_tab.dart';
import '../../features/admin/presentation/screens/admin_dispute_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_disabled_accounts_screen.dart';
import '../../features/admin/presentation/screens/admin_looking_for_report_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_report_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_review_screen.dart';
import '../../features/admin/presentation/screens/admin_seller_applications_screen.dart';
import '../../features/admin/controllers/admin_accounts_controller.dart';
import '../../features/admin/data/admin_account_service.dart';
import '../../features/admin/presentation/web/admin_accept_invite_screen.dart';
import '../../features/admin/presentation/web/admin_access_denied_screen.dart';
import '../../features/admin/presentation/web/admin_web_accounts_page.dart';
import '../../features/admin/presentation/web/admin_login_screen.dart';
import '../../features/admin/presentation/web/admin_verify_email_otp_screen.dart';
import '../../features/admin/controllers/admin_audit_logs_controller.dart';
import '../../features/admin/data/admin_audit_service.dart';
import '../../features/admin/presentation/web/admin_web_logs_page.dart';
import '../../features/admin/presentation/web/admin_web_analytics_reports_page.dart';
import '../../features/admin/presentation/web/admin_web_disputes_page.dart';
import '../../features/admin/presentation/web/admin_web_bidding_violations_page.dart';
import '../../features/admin/presentation/web/admin_web_orders_transactions_page.dart';
import '../../features/admin/presentation/web/admin_web_shell.dart';
import '../../features/admin/presentation/web/admin_web_users_page.dart';
import '../services/shared_preferences_service.dart';
import '../services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import 'admin_auth_redirect.dart';
import 'route_names.dart';

GoRouter createAdminAppRouter({required AuthProvider authProvider}) {
  return GoRouter(
    initialLocation: RouteNames.adminLogin,
    refreshListenable: authProvider,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (holdAdminLoginForTrustedDeviceCheck(
        resolvingTrustedDevice: authProvider.isResolvingTrustedDevice,
        location: location,
      )) {
        return null;
      }
      return adminAppRedirect(
        isAuthenticated: authProvider.isAuthenticated,
        canUseAdminPortal: authProvider.canUseAdminPortal,
        isDeactivatedAdministrator: authProvider.isDeactivatedAdministrator,
        isSuperAdmin: authProvider.isSuperAdmin,
        isFullyAuthenticated: authProvider.isFullyAuthenticated,
        isEmailOtpPending: authProvider.isEmailOtpPending,
        location: location,
      );
    },
    routes: [
      GoRoute(
        path: RouteNames.adminLogin,
        builder: (_, _) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: RouteNames.adminVerifyEmailOtp,
        builder: (_, _) => const AdminVerifyEmailOtpScreen(),
      ),
      GoRoute(
        path: RouteNames.adminAccessDenied,
        builder: (_, _) => const AdminAccessDeniedScreen(),
      ),
      GoRoute(
        path: RouteNames.adminAcceptInvite,
        builder: (_, _) => const AdminAcceptInviteScreen(),
      ),
      GoRoute(
        path: RouteNames.adminHome,
        redirect: (_, _) => RouteNames.adminDashboard,
      ),
      GoRoute(
        path: RouteNames.adminApplications,
        redirect: (_, _) => RouteNames.adminVerifications,
      ),
      GoRoute(
        path: RouteNames.adminReview,
        redirect: (context, state) {
          final id = state.pathParameters['id'];
          if (id == null) return RouteNames.adminVerifications;
          return RouteNames.adminReviewFor(id);
        },
      ),
      GoRoute(
        path: RouteNames.adminReportsQueue,
        redirect: (context, state) {
          final kind = adminReportKindFromQueuePath(
            state.pathParameters['kind'] ?? '',
          );
          if (kind == null) return RouteNames.adminReportsAll;
          return RouteNames.adminReportsCategoryFor(kind);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (context) => AdminDashboardController(
                  supabase: context.read<SupabaseService>(),
                  prefs: context.read<SharedPreferencesService>(),
                ),
              ),
              ChangeNotifierProvider(
                create: (context) => AdminSellerApplicationsController(
                  supabase: context.read<SupabaseService>(),
                ),
              ),
            ],
            child: AdminWebShell(child: child),
          );
        },
        routes: [
          GoRoute(
            path: RouteNames.adminDashboard,
            builder: (_, _) => const AdminDashboardTab(webEmbedded: true),
          ),
          GoRoute(
            path: RouteNames.adminVerifications,
            builder: (_, _) =>
                const AdminSellerApplicationsScreen(webEmbedded: true),
          ),
          GoRoute(
            path: RouteNames.adminVerificationReview,
            builder: (_, state) =>
                AdminReviewScreen(verificationId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: RouteNames.adminReports,
            redirect: (_, _) => RouteNames.adminMarketplaceReports,
          ),
          GoRoute(
            path: RouteNames.adminAnalytics,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminAnalyticsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminWebAnalyticsReportsPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminMarketplaceReports,
            builder: (context, state) {
              final selection = MarketplaceReportSelection.fromQuery(
                state.uri.queryParameters['type'] ??
                    state.uri.queryParameters['category'],
              );
              return ChangeNotifierProvider(
                create: (context) => AdminMarketplaceReportsController(
                  supabase: context.read<SupabaseService>(),
                  isSuperAdmin: context.read<AuthProvider>().isSuperAdmin,
                  initialSelection: selection,
                ),
                child: const AdminWebMarketplaceReportsPage(),
              );
            },
          ),
          GoRoute(
            path: RouteNames.adminReportsAll,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminDisputesHubController(
                supabase: context.read<SupabaseService>(),
                initialCategory: AdminModerationCategory.all,
                initialStatus: adminReportListFilterFromQuery(
                  state.uri.queryParameters['status'],
                ),
              ),
              child: const AdminWebDisputesPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportsCommunity,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminDisputesHubController(
                supabase: context.read<SupabaseService>(),
                initialCategory: AdminModerationCategory.community,
                initialStatus: adminReportListFilterFromQuery(
                  state.uri.queryParameters['status'],
                ),
              ),
              child: const AdminWebDisputesPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportsOrders,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminDisputesHubController(
                supabase: context.read<SupabaseService>(),
                initialCategory: AdminModerationCategory.order,
                initialStatus: adminReportListFilterFromQuery(
                  state.uri.queryParameters['status'],
                ),
              ),
              child: const AdminWebDisputesPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportsLookingFor,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminDisputesHubController(
                supabase: context.read<SupabaseService>(),
                initialCategory: AdminModerationCategory.lookingFor,
                initialStatus: adminReportListFilterFromQuery(
                  state.uri.queryParameters['status'],
                ),
              ),
              child: const AdminWebDisputesPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportDetail,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminReportsController(
                supabase: context.read<SupabaseService>(),
                reportId: state.pathParameters['id'],
              ),
              child: const AdminReportDetailScreen(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminLookingForReport,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminLookingForReportController(
                supabase: context.read<SupabaseService>(),
                reportId: state.pathParameters['id']!,
              ),
              child: const AdminLookingForReportDetailScreen(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminUsers,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminUsersController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminWebUsersPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminDisabledAccounts,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminDisabledAccountsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminDisabledAccountsScreen(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminOrders,
            redirect: (_, _) => RouteNames.adminOrdersTransactionsTab(),
          ),
          GoRoute(
            path: RouteNames.adminBiddingViolations,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminBiddingViolationsController(
                service: AdminBiddingViolationsService(
                  supabase: context.read<SupabaseService>(),
                ),
                initialStatus:
                    state.uri.queryParameters['enforcement'] ==
                        'needs_attention'
                    ? BiddingRestrictionStatusFilter.needsAttention
                    : BiddingRestrictionStatusFilter.all,
              ),
              child: const AdminWebBiddingViolationsPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminOrdersTransactions,
            builder: (context, state) {
              final orderId = state.uri.queryParameters['order'];
              final category = AdminOrderCategoryX.fromQuery(
                state.uri.queryParameters['category'],
              );
              return ChangeNotifierProvider(
                create: (context) => AdminOrdersListController(
                  supabase: context.read<SupabaseService>(),
                  initialCategory: category,
                  initialStatus: adminUnifiedStatusFromQuery(
                    state.uri.queryParameters['status'],
                  ),
                ),
                child: AdminWebOrdersTransactionsPage(initialOrderId: orderId),
              );
            },
          ),
          GoRoute(
            path: RouteNames.adminOrderDetail,
            redirect: (_, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return RouteNames.adminOrdersTransactions;
              }
              return RouteNames.adminOrderDetailModalFor(id);
            },
          ),
          GoRoute(
            path: RouteNames.adminTransactions,
            redirect: (_, _) => RouteNames.adminOrdersTransactions,
          ),
          GoRoute(
            path: RouteNames.adminDisputes,
            redirect: (_, _) => RouteNames.adminReportsAll,
          ),
          GoRoute(
            path: RouteNames.adminDisputeDetail,
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => AdminDisputesController(
                supabase: context.read<SupabaseService>(),
                disputeId: state.pathParameters['id'],
              ),
              child: const AdminDisputeDetailScreen(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminBidRiskEvents,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminBidRiskController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminBidRiskEventsScreen(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminAdministrators,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminAccountsController(
                service: AdminAccountService(context.read<SupabaseService>()),
              ),
              child: const AdminWebAccountsPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminLogs,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminAuditLogsController(
                service: AdminAuditService(context.read<SupabaseService>()),
              ),
              child: const AdminWebLogsPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminSettings,
            redirect: (_, _) => RouteNames.adminDashboard,
          ),
          GoRoute(
            path: RouteNames.adminProfile,
            redirect: (_, _) => RouteNames.adminDashboard,
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
