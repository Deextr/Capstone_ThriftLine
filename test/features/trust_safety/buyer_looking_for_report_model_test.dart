import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/buyer_looking_for_report_model.dart';
import 'package:thriftline/models/community_report_model.dart';

void main() {
  group('BuyerLookingForReportModel.fromSupabase', () {
    test('uses snapshots when live post is unavailable', () {
      final report = BuyerLookingForReportModel.fromSupabase({
        'report_id': '11111111-1111-1111-1111-111111111111',
        'post_id': '22222222-2222-2222-2222-222222222222',
        'reporter_id': '33333333-3333-3333-3333-333333333333',
        'reported_user_id': '44444444-4444-4444-4444-444444444444',
        'reason': 'spam',
        'details': 'Details here',
        'status': 'action_taken',
        'created_at': '2026-01-15T08:00:00Z',
        'resolved_at': '2026-01-16T08:00:00Z',
        'decision_outcome': 'violation_confirmed',
        'snapshot_title': 'Vintage denim jacket',
        'snapshot_description': 'Looking for size M',
      });

      expect(report.displayPostTitle, 'Vintage denim jacket');
      expect(report.displayPostDescription, 'Looking for size M');
      expect(report.livePostAvailable, isFalse);
      expect(report.status, 'action_taken');
    });

    test('prefers live post title when provided separately', () {
      final report = BuyerLookingForReportModel.fromSupabase(
        {
          'report_id': '11111111-1111-1111-1111-111111111111',
          'post_id': '22222222-2222-2222-2222-222222222222',
          'reporter_id': '33333333-3333-3333-3333-333333333333',
          'reported_user_id': '44444444-4444-4444-4444-444444444444',
          'reason': 'spam',
          'details': 'Details here',
          'status': 'under_review',
          'created_at': '2026-01-15T08:00:00Z',
          'snapshot_title': 'Snapshot title',
        },
        livePost: {'title': 'Live title', 'description': 'Live description'},
      );

      expect(report.displayPostTitle, 'Snapshot title');
      expect(report.postTitle, 'Live title');
      expect(report.livePostAvailable, isTrue);
    });
  });

  group('ReportEvidenceItem.fromSupabase', () {
    test('reads looking for evidence_id column', () {
      final item = ReportEvidenceItem.fromSupabase({
        'evidence_id': 'aaaa-bbbb',
        'file_path': 'uid/report/file.jpg',
        'created_at': '2026-01-15T08:00:00Z',
      });

      expect(item.id, 'aaaa-bbbb');
    });
  });
}
