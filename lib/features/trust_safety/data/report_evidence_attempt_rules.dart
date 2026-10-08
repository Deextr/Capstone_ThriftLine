import '../../../core/utils/report_status.dart';
import 'report_reasons.dart';

/// Authoritative rules for report evidence rounds (community and order reports).
///
/// [evidenceAttemptCount] is the number of evidence submission rounds the
/// reporter has **completed** (initial submission counts as 1). It increments
/// only when [resubmit_report_evidence] succeeds — failed uploads/resubmits do
/// not change it.
///
/// Admin **Request more evidence** decisions do not increment this counter.
/// Each successful request moves the report to [needs_more_evidence] until the
/// reporter resubmits. Admins may request again only after the reporter has
/// submitted and the case returns to [under_review], and only while the reporter
/// still has submission capacity (count &lt; [kReportMaxEvidenceAttempts]).

const String kAdminEvidenceRequestLimitMessage =
    'Evidence request limit reached. No additional evidence requests can be sent for this dispute.';

const String kAdminEvidenceRequestPendingMessage =
    'Waiting for the reporter to submit the requested evidence.';

/// Whether the reporter may upload and call resubmit for another round.
bool canReporterSubmitAdditionalEvidence({
  required String status,
  required int evidenceAttemptCount,
}) {
  return reportStatusAllowsResubmit(status) &&
      evidenceAttemptCount < kReportMaxEvidenceAttempts;
}

/// Whether an admin may issue a new `needs_more_evidence` decision.
bool canAdminRequestMoreReportEvidence({
  required String status,
  required int evidenceAttemptCount,
}) {
  if (evidenceAttemptCount >= kReportMaxEvidenceAttempts) return false;
  if (reportStatusFromDb(status) == 'needs_more_evidence') return false;
  return true;
}

/// User-facing explanation when the Request Evidence action is disabled.
String? adminEvidenceRequestDisabledReason({
  required String status,
  required int evidenceAttemptCount,
}) {
  if (canAdminRequestMoreReportEvidence(
    status: status,
    evidenceAttemptCount: evidenceAttemptCount,
  )) {
    return null;
  }
  if (evidenceAttemptCount >= kReportMaxEvidenceAttempts) {
    return kAdminEvidenceRequestLimitMessage;
  }
  if (reportStatusFromDb(status) == 'needs_more_evidence') {
    return kAdminEvidenceRequestPendingMessage;
  }
  return kAdminEvidenceRequestLimitMessage;
}

/// True when the reporter is responding to a request and the next successful
/// resubmit will use their last allowed submission round.
bool isReporterFinalEvidenceSubmissionPending({
  required String status,
  required int evidenceAttemptCount,
}) {
  if (!canReporterSubmitAdditionalEvidence(
    status: status,
    evidenceAttemptCount: evidenceAttemptCount,
  )) {
    return false;
  }
  return evidenceAttemptCount + 1 >= kReportMaxEvidenceAttempts;
}
