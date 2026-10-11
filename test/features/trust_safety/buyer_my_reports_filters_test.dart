import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/buyer_my_reports_query.dart'
    show
        buyerMyReportsTotalPages,
        kBuyerMyReportsPageSize,
        mergeAndSortBuyerReportItems,
        paginateList;
import 'package:thriftline/features/trust_safety/data/buyer_report_filters.dart';
import 'package:thriftline/features/trust_safety/domain/buyer_report_list_item.dart';

BuyerReportListItem _item({
  required String id,
  required BuyerReportTypeFilter kind,
  required String status,
}) {
  return BuyerReportListItem(
    id: id,
    kind: kind,
    status: status,
    reasonLabel: 'Reason',
    subjectLabel: 'Subject',
    createdAt: DateTime.utc(2026, 1, id.hashCode % 28 + 1),
  );
}

void main() {
  group('buyerReportMatchesStatusFilter', () {
    test('maps awaiting evidence to needs_more_evidence', () {
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.awaitingEvidence,
          status: 'needs_more_evidence',
        ),
        isTrue,
      );
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.awaitingEvidence,
          status: 'under_review',
        ),
        isFalse,
      );
    });

    test('resolved includes action_taken', () {
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.resolved,
          status: 'action_taken',
        ),
        isTrue,
      );
    });

    test('under review maps to under_review only', () {
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.underReview,
          status: 'under_review',
        ),
        isTrue,
      );
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.underReview,
          status: 'needs_more_evidence',
        ),
        isFalse,
      );
    });

    test('closed includes terminal statuses', () {
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.closed,
          status: 'dismissed',
        ),
        isTrue,
      );
      expect(
        buyerReportMatchesStatusFilter(
          filter: BuyerReportStatusFilter.closed,
          status: 'under_review',
        ),
        isFalse,
      );
    });
  });

  group('buyerReportActiveFilterSummary', () {
    test('counts and summarizes active filters', () {
      expect(
        buyerReportActiveFilterCount(
          typeFilter: BuyerReportTypeFilter.community,
          statusFilter: BuyerReportStatusFilter.dismissed,
        ),
        2,
      );
      expect(
        buyerReportActiveFilterSummary(
          typeFilter: BuyerReportTypeFilter.community,
          statusFilter: BuyerReportStatusFilter.dismissed,
        ),
        'Community reports · Dismissed',
      );
      expect(
        buyerReportActiveFilterSummary(
          typeFilter: BuyerReportTypeFilter.all,
          statusFilter: BuyerReportStatusFilter.all,
        ),
        'All reports',
      );
    });
  });

  group('filterBuyerReportItems', () {
    final sample = [
      _item(
        id: 'c1',
        kind: BuyerReportTypeFilter.community,
        status: 'dismissed',
      ),
      _item(
        id: 'o1',
        kind: BuyerReportTypeFilter.order,
        status: 'under_review',
      ),
      _item(
        id: 'l1',
        kind: BuyerReportTypeFilter.lookingFor,
        status: 'needs_more_evidence',
      ),
    ];

    test('type and status filters combine', () {
      final filtered = filterBuyerReportItems(
        items: sample,
        typeFilter: BuyerReportTypeFilter.community,
        statusFilter: BuyerReportStatusFilter.dismissed,
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, 'c1');
    });

    test('looking for filter only', () {
      final filtered = filterBuyerReportItems(
        items: sample,
        typeFilter: BuyerReportTypeFilter.lookingFor,
        statusFilter: BuyerReportStatusFilter.all,
      );
      expect(filtered.map((e) => e.id).toList(), ['l1']);
    });
  });

  group('mergeAndSortBuyerReportItems', () {
    test('sorts newest first', () {
      final older = BuyerReportListItem(
        id: 'a',
        kind: BuyerReportTypeFilter.community,
        status: 'under_review',
        reasonLabel: 'R',
        subjectLabel: 'S',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final newer = BuyerReportListItem(
        id: 'b',
        kind: BuyerReportTypeFilter.order,
        status: 'under_review',
        reasonLabel: 'R',
        subjectLabel: 'S',
        createdAt: DateTime.utc(2026, 2, 1),
      );
      final sorted = mergeAndSortBuyerReportItems([older, newer]);
      expect(sorted.first.id, 'b');
    });
  });

  group('paginateList', () {
    test('returns five items per page', () {
      final items = List.generate(12, (i) => 'r$i');
      expect(
        paginateList(items, pageIndex: 0, pageSize: kBuyerMyReportsPageSize),
        hasLength(5),
      );
      expect(
        paginateList(items, pageIndex: 1, pageSize: kBuyerMyReportsPageSize),
        hasLength(5),
      );
      expect(
        paginateList(items, pageIndex: 2, pageSize: kBuyerMyReportsPageSize),
        ['r10', 'r11'],
      );
    });

    test('total pages', () {
      expect(buyerMyReportsTotalPages(0), 0);
      expect(buyerMyReportsTotalPages(5), 1);
      expect(buyerMyReportsTotalPages(6), 2);
    });
  });

  group('buyerReportIsOrderLinked', () {
    test('uses order id when present', () {
      expect(
        buyerReportIsOrderLinked(category: 'other', orderId: 'ord-1'),
        isTrue,
      );
    });

    test('uses category slug when no order', () {
      expect(
        buyerReportIsOrderLinked(
          category: 'item_not_as_described',
          orderId: null,
        ),
        isTrue,
      );
      expect(
        buyerReportIsOrderLinked(category: 'harassment', orderId: null),
        isFalse,
      );
    });
  });
}
