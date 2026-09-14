import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_delivery_dispute.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/trust_safety/data/report_reasons.dart';
import 'package:thriftline/models/community_report_model.dart';
import 'package:thriftline/models/enums.dart';

void main() {
  group('admin report decisions', () {
    test('only under_review can be decided', () {
      expect(canDecideReport('under_review'), isTrue);
      expect(canDecideReport('action_taken'), isFalse);
      expect(canDecideReport('resolved'), isFalse);
      expect(canDecideReport('dismissed'), isFalse);
    });

    test('accepts only Phase 8 decision values', () {
      expect(isAllowedReportDecision('action_taken'), isTrue);
      expect(isAllowedReportDecision('resolved'), isTrue);
      expect(isAllowedReportDecision('dismissed'), isTrue);
      expect(isAllowedReportDecision('accepted'), isFalse);
      expect(isAllowedReportDecision('closed'), isFalse);
      expect(isAllowedReportDecision('under_review'), isFalse);
    });

    test('open queue uses the same status as hub counts', () {
      expect(isOpenReportStatus(kAdminReportOpenStatus), isTrue);
      expect(kAdminReportOpenStatus, 'under_review');
      expect(kAdminReportClosedStatuses, [
        'action_taken',
        'resolved',
        'dismissed',
      ]);
    });

    test('requires a bounded admin response', () {
      expect(adminResponseError('short'), isNotNull);
      expect(adminResponseError('We reviewed this report.'), isNull);
      expect(adminResponseError('a' * 2001), isNotNull);
    });

    test('reuses Phase 8 status labels', () {
      expect(reportStatusLabel('under_review'), 'Under Review');
      expect(reportStatusLabel('action_taken'), 'Action Taken');
      expect(reportDecisionLabel('action_taken'), 'Action Taken');
      expect(reportDecisionLabel('resolved'), 'Resolved');
      expect(reportDecisionLabel('dismissed'), 'Dismissed');
    });
  });

  group('admin delivery problems', () {
    test('only open disputes can be closed', () {
      expect(canCloseDispute('open'), isTrue);
      expect(canCloseDispute('resolved'), isFalse);
      expect(kAdminDisputeClosedStatus, 'resolved');
    });

    test('maps Phase 7 reason values', () {
      expect(
        DeliveryDisputeReason.fromDb('parcel_not_received'),
        DeliveryDisputeReason.parcelNotReceived,
      );
      expect(DeliveryDisputeReason.fromDb('wrong_item').label, 'Wrong item');
      expect(
        DeliveryDisputeReason.fromDb('unknown'),
        DeliveryDisputeReason.other,
      );
    });

    test('allows an optional bounded note', () {
      expect(adminDisputeNoteError(''), isNull);
      expect(
        adminDisputeNoteError('Inspected photos. No refund in this phase.'),
        isNull,
      );
      expect(adminDisputeNoteError('a' * 2001), isNotNull);
    });

    test('maps a dispute without inventing courier data', () {
      final dispute = AdminDeliveryDispute.fromSupabase(
        {
          'dispute_id': 'd1',
          'order_id': 'o1',
          'shipment_id': 's1',
          'buyer_id': 'buyer-1',
          'reason': 'parcel_not_received',
          'details': 'Never arrived.',
          'status': 'open',
          'created_at': '2026-09-13T03:00:00Z',
        },
        buyer: {'username': 'maya', 'full_name': 'Maya Cruz'},
        seller: {
          'username': 'vintagevibes_ph',
          'full_name': 'Vintage Shop',
          'shop_name': 'Vintage Vibes',
        },
      );
      expect(dispute.status, 'open');
      expect(dispute.reason, DeliveryDisputeReason.parcelNotReceived);
      expect(dispute.buyerUsername, 'maya');
      expect(dispute.sellerShopName, 'Vintage Vibes');
      expect(dispute.shipment, isNull);
    });
  });

  group('admin identity display', () {
    test('shows handles without exposing private fields', () {
      expect(
        adminHandle('vintagevibes_ph', 'Vintage Shop'),
        '@vintagevibes_ph',
      );
      expect(adminHandle('', 'Maria Santos'), 'Maria Santos');
      expect(accountRoleLabel('seller'), 'Seller');
      expect(accountRoleLabel('buyer'), 'Buyer');
    });

    test('maps reporter and reported users for admin review', () {
      final report = CommunityReportModel.fromSupabase(
        {
          'report_id': 'rpt-1',
          'reporter_id': 'buyer-1',
          'reported_user_id': 'seller-1',
          'category': 'scam_or_fraud',
          'details': 'Asked me to pay outside the app.',
          'status': 'under_review',
          'admin_response': null,
          'reviewed_by': null,
          'created_at': '2026-09-13T03:00:00Z',
        },
        reportedUser: {
          'username': 'vintagevibes_ph',
          'full_name': 'Juan Dela Cruz',
          'role': 'seller',
          'shop_name': 'Vintage Vibes',
        },
        reporterUser: {
          'username': 'maya',
          'full_name': 'Maria Santos',
          'role': 'buyer',
        },
        orderNumber: 'TL-10234',
        orderTitle: 'Vintage Lacoste Polo',
      );
      expect(report.reportedUsername, 'vintagevibes_ph');
      expect(report.reporterUsername, 'maya');
      expect(report.reportedRole, 'seller');
      expect(report.orderNumber, 'TL-10234');
      expect(report.orderTitle, 'Vintage Lacoste Polo');
    });

    test('status chips always have readable text', () {
      expect(verificationStatusLabel('pending'), 'Pending');
      expect(verificationStatusLabel('approved'), 'Approved');
      expect(verificationStatusLabel('rejected'), 'Rejected');
      expect(disputeStatusLabel('open'), 'Open');
      expect(disputeStatusLabel('resolved'), 'Resolved');
      expect(adminQueueFilterLabel(AdminQueueFilter.open), 'Open');
      expect(adminQueueFilterLabel(AdminQueueFilter.closed), 'Closed');
    });

    test('admin labels do not use emojis', () {
      final labels = [
        ...kAdminReportDecisions.map(reportDecisionLabel),
        ...[
          'under_review',
          'action_taken',
          'resolved',
          'dismissed',
        ].map(reportStatusLabel),
        verificationStatusLabel('pending'),
        disputeStatusLabel('open'),
        adminEvidenceCountLabel(3),
      ];
      for (final label in labels) {
        expect(
          label.contains(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true)),
          isFalse,
        );
      }
    });
  });

  group('unauthorized messaging', () {
    test('maps admin-only RPC failures to a safe message', () {
      expect(
        adminFriendlyError(
          Exception('Only an admin can review reports.'),
          'Could not save that decision.',
        ),
        'Only an admin can take this action.',
      );
      expect(
        adminFriendlyError(
          Exception('PostgrestException: permission denied for table reports'),
          'Could not save that decision.',
        ),
        'Could not save that decision.',
      );
    });
  });
}
