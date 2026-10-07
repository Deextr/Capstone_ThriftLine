import '../../../models/community_report_model.dart';
import '../../../models/enums.dart';
import '../../../models/order_model.dart';
import '../../trust_safety/data/report_reasons.dart';
import '../presentation/widgets/admin_case_detail_widgets.dart';
import 'admin_review_rules.dart';

/// Stages stuck longer than this may show a warning on the timeline.
const Duration kAdminOrderStageStallThreshold = Duration(hours: 72);

List<AdminCaseTimelineEvent> buildAdminOrderReportCaseTimeline({
  required CommunityReportModel report,
  OrderModel? order,
}) {
  final events = <AdminCaseTimelineEvent>[];
  final now = DateTime.now();

  if (order != null) {
    events.addAll(_orderLifecycleEvents(order, now));
  }

  events.add(
    AdminCaseTimelineEvent(
      title: 'Report submitted',
      at: report.createdAt,
      isComplete: true,
    ),
  );

  if (report.status == kAdminReportNeedsEvidenceStatus) {
    final instruction = report.reporterInstruction?.trim();
    if (instruction != null && instruction.isNotEmpty) {
      events.add(
        AdminCaseTimelineEvent(
          title: 'Evidence requested',
          at: report.resolvedAt,
          isComplete: true,
        ),
      );
    }
    events.add(
      const AdminCaseTimelineEvent(
        title: 'Awaiting new evidence',
        isComplete: false,
        isCurrent: true,
      ),
    );
    return events;
  }

  if (canDecideReport(report.status)) {
    events.add(
      const AdminCaseTimelineEvent(
        title: 'Under admin review',
        isComplete: false,
        isCurrent: true,
      ),
    );
    return events;
  }

  events.add(
    AdminCaseTimelineEvent(
      title: reportStatusLabel(report.status),
      at: report.resolvedAt,
      isComplete: true,
    ),
  );

  if (report.resolutionFinancial == 'release_seller') {
    events.add(
      const AdminCaseTimelineEvent(
        title: 'Payment released to seller',
        isComplete: true,
      ),
    );
  } else if (report.resolutionFinancial == 'refund_buyer') {
    events.add(
      const AdminCaseTimelineEvent(title: 'Buyer refunded', isComplete: true),
    );
  }

  return events;
}

List<AdminCaseTimelineEvent> _orderLifecycleEvents(
  OrderModel order,
  DateTime now,
) {
  final events = <AdminCaseTimelineEvent>[];
  final shipment = order.shipment;
  final paid = order.paymentStatus.trim().toLowerCase() == 'paid';

  events.add(
    AdminCaseTimelineEvent(
      title: 'Order placed',
      at: order.createdAt,
      isComplete: true,
    ),
  );

  if (paid ||
      _statusIndex(order.status) >=
          _statusIndex(OrderStatus.paymentConfirmed)) {
    events.add(
      AdminCaseTimelineEvent(
        title: 'Payment confirmed',
        at: order.createdAt,
        isComplete: true,
      ),
    );
  }

  final preparingCurrent =
      order.status == OrderStatus.preparing ||
      order.status == OrderStatus.paymentConfirmed;
  if (preparingCurrent ||
      _statusIndex(order.status) > _statusIndex(OrderStatus.preparing)) {
    final at = shipment?.readyForPickupAt ?? order.createdAt;
    final stalled =
        preparingCurrent && now.difference(at) > kAdminOrderStageStallThreshold;
    events.add(
      AdminCaseTimelineEvent(
        title: 'Preparing order',
        at: at,
        isComplete: !preparingCurrent,
        isCurrent: preparingCurrent,
        emphasisWarning: stalled,
        subtitle: stalled
            ? 'Paid but not shipped for over 72 hours — review fulfillment.'
            : null,
      ),
    );
  }

  void addShipmentStep({
    required String title,
    DateTime? at,
    required bool reached,
    bool isCurrent = false,
  }) {
    if (!reached && at == null) return;
    events.add(
      AdminCaseTimelineEvent(
        title: title,
        at: at,
        isComplete: reached && !isCurrent,
        isCurrent: isCurrent,
      ),
    );
  }

  final shippedOrLater =
      _statusIndex(order.status) >= _statusIndex(OrderStatus.shipped);
  addShipmentStep(
    title: 'Shipped',
    at: shipment?.pickedUpAt ?? shipment?.readyForPickupAt,
    reached: shippedOrLater,
    isCurrent: order.status == OrderStatus.shipped,
  );

  final outOrLater =
      _statusIndex(order.status) >= _statusIndex(OrderStatus.outForDelivery);
  addShipmentStep(
    title: 'Out for delivery',
    at: shipment?.outForDeliveryAt,
    reached: outOrLater,
    isCurrent: order.status == OrderStatus.outForDelivery,
  );

  final deliveredOrLater =
      _statusIndex(order.status) >= _statusIndex(OrderStatus.delivered);
  addShipmentStep(
    title: 'Delivered',
    at: shipment?.deliveryVerifiedAt ?? shipment?.buyerConfirmedReceivedAt,
    reached: deliveredOrLater,
    isCurrent: order.status == OrderStatus.delivered,
  );

  if (order.status == OrderStatus.completed) {
    events.add(
      AdminCaseTimelineEvent(
        title: 'Order completed',
        at: shipment?.completedAt,
        isComplete: true,
      ),
    );
  }

  if (order.status == OrderStatus.cancelled) {
    events.add(
      const AdminCaseTimelineEvent(title: 'Order cancelled', isComplete: true),
    );
  }

  return events;
}

int _statusIndex(OrderStatus status) {
  return switch (status) {
    OrderStatus.placed => 0,
    OrderStatus.paymentPending => 1,
    OrderStatus.paymentConfirmed => 2,
    OrderStatus.preparing => 3,
    OrderStatus.shipped => 4,
    OrderStatus.outForDelivery => 5,
    OrderStatus.delivered => 6,
    OrderStatus.completed => 7,
    OrderStatus.disputed => 6,
    OrderStatus.cancelled => -1,
  };
}
