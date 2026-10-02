import 'package:go_router/go_router.dart';

import '../../../core/routes/route_names.dart';
import '../../../features/auth/domain/account_mode.dart';
import '../../../models/enums.dart';
import '../../../models/notification_model.dart';

/// Opens the correct destination for a notification in the active workspace.
void openNotification(
  GoRouter router, {
  required NotificationModel notification,
  required AccountMode activeAccount,
}) {
  final reportId = notificationAppealReportId(notification.data);
  if (reportId != null) {
    router.push(RouteNames.accountReviewFor(reportId));
    return;
  }

  if (notification.type == NotificationType.reportDecision) {
    router.push(RouteNames.myReports);
    return;
  }

  final orderId = notification.data['order_id']?.trim();
  if (orderId != null && orderId.isNotEmpty) {
    if (activeAccount == AccountMode.seller &&
        notification.audience == NotificationAudience.seller) {
      router.push('/seller-order/$orderId');
      return;
    }
    if (activeAccount == AccountMode.buyer &&
        notification.audience == NotificationAudience.buyer) {
      router.push(RouteNames.trackOrderFor(orderId));
      return;
    }
  }

  final auctionId = notification.data['auction_id']?.trim();
  if (auctionId != null &&
      auctionId.isNotEmpty &&
      activeAccount == AccountMode.buyer) {
    router.push(RouteNames.homeBidding);
    return;
  }

  if (notification.type == NotificationType.verificationSubmitted ||
      notification.type == NotificationType.verificationApproved ||
      notification.type == NotificationType.verificationRejected) {
    if (activeAccount == AccountMode.seller) {
      router.push(RouteNames.becomeSeller);
    }
    return;
  }
}
