import '../../../core/utils/report_status.dart';
import '../domain/buyer_report_list_item.dart';
import 'report_reasons.dart' show reportStatusIsClosed;

/// Report categories shown in Buyer → My Reports.
enum BuyerReportTypeFilter { all, community, order, lookingFor }

/// User-facing status filters mapped to existing [report_status_enum] values.
///
/// There is no separate DB value for "pending" — new reports use [underReview].
/// [closed] matches any terminal status (resolved, action_taken, dismissed).
enum BuyerReportStatusFilter {
  all,
  underReview,
  awaitingEvidence,
  resolved,
  dismissed,
  closed,
}

const List<BuyerReportStatusFilter> kBuyerReportStatusFilterOptions = [
  BuyerReportStatusFilter.all,
  BuyerReportStatusFilter.underReview,
  BuyerReportStatusFilter.awaitingEvidence,
  BuyerReportStatusFilter.resolved,
  BuyerReportStatusFilter.dismissed,
  BuyerReportStatusFilter.closed,
];

const List<BuyerReportTypeFilter> kBuyerReportTypeFilterOptions =
    BuyerReportTypeFilter.values;

const Set<String> kBuyerOrderLinkedReportReasons = {
  'seller_not_processing_order',
  'counterfeit_received',
  'item_not_as_described',
  'undisclosed_damage',
  'buyer_delivery_pin_issue',
  'fake_product',
  'counterfeit_item',
  'failure_to_ship',
};

bool buyerReportIsOrderLinked({required String category, String? orderId}) {
  if (orderId != null && orderId.trim().isNotEmpty) return true;
  return kBuyerOrderLinkedReportReasons.contains(category);
}

String buyerReportTypeFilterLabel(BuyerReportTypeFilter filter) =>
    switch (filter) {
      BuyerReportTypeFilter.all => 'All',
      BuyerReportTypeFilter.community => 'Community',
      BuyerReportTypeFilter.order => 'Order',
      BuyerReportTypeFilter.lookingFor => 'Looking For',
    };

/// Long labels for filter summary and bottom sheet.
String buyerReportTypeSheetLabel(BuyerReportTypeFilter filter) =>
    switch (filter) {
      BuyerReportTypeFilter.all => 'All reports',
      BuyerReportTypeFilter.community => 'Community reports',
      BuyerReportTypeFilter.order => 'Order reports',
      BuyerReportTypeFilter.lookingFor => 'Looking for reports',
    };

String buyerReportStatusFilterLabel(BuyerReportStatusFilter filter) =>
    switch (filter) {
      BuyerReportStatusFilter.all => 'All',
      BuyerReportStatusFilter.underReview => 'Under review',
      BuyerReportStatusFilter.awaitingEvidence => 'Awaiting evidence',
      BuyerReportStatusFilter.resolved => 'Resolved',
      BuyerReportStatusFilter.dismissed => 'Dismissed',
      BuyerReportStatusFilter.closed => 'Closed',
    };

String buyerReportStatusSheetLabel(BuyerReportStatusFilter filter) =>
    switch (filter) {
      BuyerReportStatusFilter.all => 'All statuses',
      BuyerReportStatusFilter.underReview => 'Under review',
      BuyerReportStatusFilter.awaitingEvidence => 'Awaiting evidence',
      BuyerReportStatusFilter.resolved => 'Resolved',
      BuyerReportStatusFilter.dismissed => 'Dismissed',
      BuyerReportStatusFilter.closed => 'Closed',
    };

int buyerReportActiveFilterCount({
  required BuyerReportTypeFilter typeFilter,
  required BuyerReportStatusFilter statusFilter,
}) {
  var count = 0;
  if (typeFilter != BuyerReportTypeFilter.all) count++;
  if (statusFilter != BuyerReportStatusFilter.all) count++;
  return count;
}

String buyerReportActiveFilterSummary({
  required BuyerReportTypeFilter typeFilter,
  required BuyerReportStatusFilter statusFilter,
}) {
  if (buyerReportActiveFilterCount(
        typeFilter: typeFilter,
        statusFilter: statusFilter,
      ) ==
      0) {
    return 'All reports';
  }
  final parts = <String>[];
  if (typeFilter != BuyerReportTypeFilter.all) {
    parts.add(buyerReportTypeSheetLabel(typeFilter));
  }
  if (statusFilter != BuyerReportStatusFilter.all) {
    parts.add(buyerReportStatusSheetLabel(statusFilter));
  }
  return parts.join(' · ');
}

String buyerReportKindLabel(BuyerReportTypeFilter kind) => switch (kind) {
  BuyerReportTypeFilter.community => 'Community',
  BuyerReportTypeFilter.order => 'Order',
  BuyerReportTypeFilter.lookingFor => 'Looking For',
  BuyerReportTypeFilter.all => 'Report',
};

/// Whether a unified list item matches the selected type filter.
bool buyerReportMatchesTypeFilter({
  required BuyerReportTypeFilter filter,
  required BuyerReportTypeFilter itemKind,
}) {
  if (filter == BuyerReportTypeFilter.all) return true;
  return filter == itemKind;
}

/// Maps UI status filters to normalized DB status slugs.
bool buyerReportMatchesStatusFilter({
  required BuyerReportStatusFilter filter,
  required String status,
}) {
  if (filter == BuyerReportStatusFilter.all) return true;
  final normalized = reportStatusFromDb(status);
  return switch (filter) {
    BuyerReportStatusFilter.underReview => normalized == 'under_review',
    BuyerReportStatusFilter.awaitingEvidence =>
      normalized == 'needs_more_evidence',
    BuyerReportStatusFilter.resolved =>
      normalized == 'resolved' || normalized == 'action_taken',
    BuyerReportStatusFilter.dismissed => normalized == 'dismissed',
    BuyerReportStatusFilter.closed => reportStatusIsClosed(status),
    BuyerReportStatusFilter.all => true,
  };
}

BuyerReportTypeFilter buyerReportKindFromCommunityRow({
  required String category,
  String? orderId,
}) {
  return buyerReportIsOrderLinked(category: category, orderId: orderId)
      ? BuyerReportTypeFilter.order
      : BuyerReportTypeFilter.community;
}

List<BuyerReportListItem> filterBuyerReportItems({
  required Iterable<BuyerReportListItem> items,
  required BuyerReportTypeFilter typeFilter,
  required BuyerReportStatusFilter statusFilter,
}) {
  return items
      .where(
        (item) =>
            buyerReportMatchesTypeFilter(
              filter: typeFilter,
              itemKind: item.kind,
            ) &&
            buyerReportMatchesStatusFilter(
              filter: statusFilter,
              status: item.status,
            ),
      )
      .toList();
}

String buyerLookingForDecisionOutcomeLabel(String? outcome) {
  return switch (outcome?.trim().toLowerCase()) {
    'violation_confirmed' => 'Violation confirmed',
    'dismissed' => 'Dismissed',
    'insufficient_evidence' => 'Insufficient evidence',
    _ => '',
  };
}
