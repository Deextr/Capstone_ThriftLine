import 'package:flutter/material.dart';

import 'admin_report_decision_content.dart';

const String kLookingForDecisionRemovePost = 'remove_post';
const String kLookingForDecisionDismissReport = 'dismiss_report';

/// Legacy RPC slug; not offered in the Looking For dispute review modal.
const String kLookingForDecisionRequestEvidence = 'needs_more_evidence';

const List<CommunityDisputeDecisionOptionData>
kLookingForDisputeDecisionOptions = [
  CommunityDisputeDecisionOptionData(
    value: kLookingForDecisionRemovePost,
    title: 'Remove Post',
    description:
        'The post breaks Looking For guidelines and should not stay public.',
    icon: Icons.visibility_off_outlined,
  ),
  CommunityDisputeDecisionOptionData(
    value: kLookingForDecisionDismissReport,
    title: 'Dismiss Report',
    description:
        'No violation is established; keep the post available if it still complies.',
    icon: Icons.check_circle_outline_rounded,
  ),
];

String? lookingForDecisionToRpc(String? uiDecision) => switch (uiDecision) {
  kLookingForDecisionRemovePost => 'resolved',
  kLookingForDecisionDismissReport => 'dismissed',
  kLookingForDecisionRequestEvidence => 'needs_more_evidence',
  _ => null,
};

bool lookingForDecisionRequiresViolation(String? uiDecision) =>
    uiDecision == kLookingForDecisionRemovePost;

String lookingForDisputeActionLabel(String? uiDecision) => switch (uiDecision) {
  kLookingForDecisionRemovePost => 'Remove Post',
  kLookingForDecisionDismissReport => 'Dismiss Report',
  kLookingForDecisionRequestEvidence => 'Send Evidence Request',
  _ => 'Choose an action',
};

String lookingForDisputeConfirmTitle(String? uiDecision) =>
    switch (uiDecision) {
      kLookingForDecisionRemovePost => 'Confirm post removal',
      kLookingForDecisionDismissReport => 'Confirm dismissal',
      kLookingForDecisionRequestEvidence => 'Confirm evidence request',
      _ => 'Confirm decision',
    };

String lookingForDisputeConfirmDetail(
  String? uiDecision,
) => switch (uiDecision) {
  kLookingForDecisionRemovePost =>
    'The Looking For post will be marked removed by moderation and cannot be '
        'reposted. Strike rules may apply once per post. Other open reports on '
        'this post will close with the same enforcement without duplicate strikes.',
  kLookingForDecisionDismissReport =>
    'The report will be closed. No strike or removal is applied. Other open '
        'reports on this post stay open unless you decide them separately.',
  kLookingForDecisionRequestEvidence =>
    'The reporter will be asked to submit additional evidence.',
  _ => '',
};

List<AdminResponseTemplate> lookingForDecisionReasonTemplates(
  String uiDecision,
) {
  const custom = AdminResponseTemplate(
    id: 'custom',
    label: 'Custom explanation',
    message: '',
  );
  return switch (uiDecision) {
    kLookingForDecisionRemovePost => [
      const AdminResponseTemplate(
        id: 'spam',
        label: 'Spam or repetitive posting',
        message:
            'We removed this Looking For post because it qualifies as spam or repetitive promotional content.',
      ),
      const AdminResponseTemplate(
        id: 'unrelated',
        label: 'Unrelated content',
        message:
            'We removed this post because it is not related to thrift or marketplace buying requests.',
      ),
      const AdminResponseTemplate(
        id: 'inappropriate',
        label: 'Inappropriate or explicit content',
        message:
            'We removed this post because it contains inappropriate or explicit content.',
      ),
      const AdminResponseTemplate(
        id: 'suspicious',
        label: 'Suspicious or fraudulent content',
        message:
            'We removed this post because it appears suspicious or may mislead other members.',
      ),
      const AdminResponseTemplate(
        id: 'prohibited',
        label: 'Prohibited content',
        message:
            'We removed this post because it violates prohibited content rules.',
      ),
      custom,
    ],
    kLookingForDecisionDismissReport => [
      const AdminResponseTemplate(
        id: 'no_violation',
        label: 'No violation found',
        message:
            'We reviewed this report and did not find sufficient grounds for moderation.',
      ),
      const AdminResponseTemplate(
        id: 'duplicate_report',
        label: 'Duplicate or mistaken report',
        message:
            'This report appears duplicate or mistaken. No action was taken on the post.',
      ),
      custom,
    ],
    _ => [custom],
  };
}
