import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/report_reasons.dart';

void main() {
  group('evidence resubmission rules', () {
    test('three total attempts constant', () {
      expect(kReportMaxEvidenceAttempts, 3);
    });

    test('resubmit only when needs_more_evidence', () {
      expect(reportStatusAllowsResubmit('needs_more_evidence'), isTrue);
      expect(reportStatusAllowsResubmit('under_review'), isFalse);
      expect(reportStatusAllowsResubmit('resolved'), isFalse);
    });

    test('community reasons exclude order-only slugs', () {
      expect(
        kCommunityReportReasons.any((r) => r.slug == 'item_not_as_described'),
        isFalse,
      );
      expect(
        kOrderBuyerReportReasons.any((r) => r.slug == 'item_not_as_described'),
        isTrue,
      );
    });
  });
}
