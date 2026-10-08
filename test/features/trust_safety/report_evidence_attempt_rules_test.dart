import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/report_evidence_attempt_rules.dart';
import 'package:thriftline/features/trust_safety/data/report_reasons.dart';

void main() {
  group('report evidence attempt rules', () {
    test('max attempts constant is three submission rounds', () {
      expect(kReportMaxEvidenceAttempts, 3);
    });

    test('reporter can submit while needs_more_evidence and under max', () {
      expect(
        canReporterSubmitAdditionalEvidence(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 1,
        ),
        isTrue,
      );
      expect(
        canReporterSubmitAdditionalEvidence(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 2,
        ),
        isTrue,
      );
      expect(
        canReporterSubmitAdditionalEvidence(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 3,
        ),
        isFalse,
      );
    });

    test('reporter cannot submit when not waiting for evidence', () {
      expect(
        canReporterSubmitAdditionalEvidence(
          status: 'under_review',
          evidenceAttemptCount: 1,
        ),
        isFalse,
      );
    });

    test(
      'admin can request only from under_review with submission headroom',
      () {
        expect(
          canAdminRequestMoreReportEvidence(
            status: 'under_review',
            evidenceAttemptCount: 1,
          ),
          isTrue,
        );
        expect(
          canAdminRequestMoreReportEvidence(
            status: 'under_review',
            evidenceAttemptCount: 2,
          ),
          isTrue,
        );
        expect(
          canAdminRequestMoreReportEvidence(
            status: 'under_review',
            evidenceAttemptCount: 3,
          ),
          isFalse,
        );
      },
    );

    test('admin cannot request while reporter response is pending', () {
      expect(
        canAdminRequestMoreReportEvidence(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 1,
        ),
        isFalse,
      );
      expect(
        canAdminRequestMoreReportEvidence(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 2,
        ),
        isFalse,
      );
      expect(
        adminEvidenceRequestDisabledReason(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 2,
        ),
        kAdminEvidenceRequestPendingMessage,
      );
    });

    test('admin limit message when submission rounds exhausted', () {
      expect(
        adminEvidenceRequestDisabledReason(
          status: 'under_review',
          evidenceAttemptCount: 3,
        ),
        kAdminEvidenceRequestLimitMessage,
      );
    });

    test('final submission warning only on last permitted resubmit', () {
      expect(
        isReporterFinalEvidenceSubmissionPending(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 1,
        ),
        isFalse,
      );
      expect(
        isReporterFinalEvidenceSubmissionPending(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 2,
        ),
        isTrue,
      );
      expect(
        isReporterFinalEvidenceSubmissionPending(
          status: 'needs_more_evidence',
          evidenceAttemptCount: 3,
        ),
        isFalse,
      );
    });
  });
}
