import '../data/buyer_report_filters.dart';

/// Unified row for Buyer → My Reports (all report sources).
class BuyerReportListItem {
  const BuyerReportListItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.reasonLabel,
    required this.subjectLabel,
    required this.createdAt,
  });

  final String id;
  final BuyerReportTypeFilter kind;
  final String status;
  final String reasonLabel;
  final String subjectLabel;
  final DateTime createdAt;

  String get kindLabel => buyerReportKindLabel(kind);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuyerReportListItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(id, kind);
}
