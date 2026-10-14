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

  final reportIdPlain = notification.data['report_id']?.trim();
  if (reportIdPlain != null &&
      reportIdPlain.isNotEmpty &&
      notification.type == NotificationType.system &&
      notification.data['can_appeal'] != 'true') {
    router.push(RouteNames.myReports);
    return;
  }

  final conversationId = notification.data['conversation_id']?.trim();
  if (notification.type == NotificationType.message &&
      conversationId != null &&
      conversationId.isNotEmpty) {
    router.push(RouteNames.chatThread(conversationId));
    return;
  }

  final postId = notification.data['post_id']?.trim();
  if (postId != null && postId.isNotEmpty) {
    router.push(RouteNames.lookingForPost(postId));
    return;
  }

  final orderId = notification.data['order_id']?.trim();
  final event = notification.data['event']?.trim();
  if (orderId != null && orderId.isNotEmpty) {
    if (activeAccount == AccountMode.buyer &&
        (event == 'second_chance_offer' ||
            event == 'fallback_offer' ||
            notification.type == NotificationType.wonBid)) {
      router.push(RouteNames.paymentForOrder(orderId));
      return;
    }
    if (activeAccount == AccountMode.seller &&
        (notification.audience == NotificationAudience.seller ||
            notification.data.containsKey('order_id'))) {
      router.push('/seller-order/$orderId');
      return;
    }
    if (activeAccount == AccountMode.buyer &&
        (notification.audience == NotificationAudience.buyer ||
            notification.type == NotificationType.orderConfirmed ||
            notification.type == NotificationType.shipped)) {
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

  if (notification.data.containsKey('payout_id') &&
      activeAccount == AccountMode.seller) {
    router.push(RouteNames.sellerHome);
    return;
  }
}
