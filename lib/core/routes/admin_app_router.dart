import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/admin/controllers/admin_bid_risk_controller.dart';
import '../../features/admin/controllers/admin_dashboard_controller.dart';
import '../../features/admin/controllers/admin_disabled_accounts_controller.dart';
import '../../features/admin/controllers/admin_disputes_controller.dart';
import '../../features/admin/controllers/admin_looking_for_report_controller.dart';
import '../../features/admin/controllers/admin_orders_list_controller.dart';
import '../../features/admin/controllers/admin_reports_controller.dart';
import '../../features/admin/controllers/admin_seller_applications_controller.dart';
import '../../features/admin/controllers/admin_transactions_controller.dart';
import '../../features/admin/controllers/admin_users_controller.dart';
import '../../features/admin/data/admin_review_rules.dart';
import '../../features/admin/presentation/screens/admin_bid_risk_events_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_tab.dart';
import '../../features/admin/presentation/screens/admin_dispute_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_disputes_queue_screen.dart';
import '../../features/admin/presentation/screens/admin_disabled_accounts_screen.dart';
import '../../features/admin/presentation/screens/admin_looking_for_report_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_report_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_reports_hub_screen.dart';
import '../../features/admin/presentation/screens/admin_reports_queue_screen.dart';
import '../../features/admin/presentation/screens/admin_review_screen.dart';
import '../../features/admin/presentation/screens/admin_seller_applications_screen.dart';
import '../../features/admin/presentation/web/admin_access_denied_screen.dart';
import '../../features/admin/presentation/web/admin_login_screen.dart';
import '../../features/admin/presentation/web/admin_verify_email_otp_screen.dart';
import '../../features/admin/controllers/admin_audit_logs_controller.dart';
import '../../features/admin/data/admin_audit_service.dart';
import '../../features/admin/presentation/web/admin_web_logs_page.dart';
import '../../features/admin/presentation/web/admin_web_order_detail_page.dart';
import '../../features/admin/presentation/web/admin_web_orders_page.dart';
import '../../features/admin/presentation/web/admin_web_settings_page.dart';
import '../../features/admin/presentation/web/admin_web_shell.dart';
import '../../features/admin/presentation/web/admin_web_transactions_page.dart';
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
        isAdmin: authProvider.isAdmin,
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
          if (kind == null) return RouteNames.adminReports;
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
                create: (context) => AdminReportsController(
                  supabase: context.read<SupabaseService>(),
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
            builder: (_, _) => const AdminSellerApplicationsScreen(
              webEmbedded: true,
            ),
          ),
          GoRoute(
            path: RouteNames.adminVerificationReview,
            builder: (_, state) => AdminReviewScreen(
              verificationId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: RouteNames.adminReports,
            builder: (_, _) => const AdminReportsHubScreen(embedded: true),
          ),
          GoRoute(
            path: RouteNames.adminReportsCommunity,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminReportsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminReportsQueueScreen(
                kind: AdminReportKind.community,
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportsOrders,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminReportsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminReportsQueueScreen(kind: AdminReportKind.order),
            ),
          ),
          GoRoute(
            path: RouteNames.adminReportsLookingFor,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminReportsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminReportsQueueScreen(
                kind: AdminReportKind.lookingFor,
              ),
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
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminOrdersListController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminWebOrdersPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminOrderDetail,
            builder: (_, state) => AdminWebOrderDetailPage(
              orderId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: RouteNames.adminTransactions,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminTransactionsController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminWebTransactionsPage(),
            ),
          ),
          GoRoute(
            path: RouteNames.adminDisputes,
            builder: (context, _) => ChangeNotifierProvider(
              create: (context) => AdminDisputesController(
                supabase: context.read<SupabaseService>(),
              ),
              child: const AdminDisputesQueueScreen(),
            ),
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
              create: (context) =>
                  AdminBidRiskController(supabase: context.read<SupabaseService>()),
              child: const AdminBidRiskEventsScreen(),
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
            builder: (_, _) => const AdminWebSettingsPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
