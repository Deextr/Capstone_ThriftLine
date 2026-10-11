import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/domain/looking_for_report_moderation.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);

  group('Looking For report moderation labels', () {
    test('expired review required when open and past expiry', () {
      expect(
        lookingForModerationStatusDisplayLabel(
          status: 'under_review',
          expiresAt: now.subtract(const Duration(hours: 6)),
          serverNow: now,
        ),
        'Expired — Review Required',
      );
    });

    test('review target bands', () {
      expect(
        lookingForReportReviewTargetBand(
          reportCreatedAt: now.subtract(const Duration(hours: 3)),
          serverNow: now,
        ),
        LookingForReportReviewTargetBand.withinTarget,
      );
      expect(
        lookingForReportReviewTargetLabel(
          lookingForReportReviewTargetBand(
            reportCreatedAt: now.subtract(const Duration(hours: 22)),
            serverNow: now,
          ),
        ),
        'Review soon',
      );
      expect(
        lookingForReportReviewTargetLabel(
          lookingForReportReviewTargetBand(
            reportCreatedAt: now.subtract(const Duration(hours: 31)),
            serverNow: now,
          ),
        ),
        'Overdue',
      );
    });

    test('priority favors severe reason over newer mild report', () {
      final cmp = compareLookingForReportPriority(
        reasonA: 'scam_or_suspicious',
        statusA: 'under_review',
        expiresA: now.add(const Duration(days: 2)),
        createdA: now.subtract(const Duration(hours: 1)),
        openA: 1,
        violationsA: 0,
        reasonB: 'spam',
        statusB: 'under_review',
        expiresB: now.add(const Duration(hours: 2)),
        createdB: now,
        openB: 1,
        violationsB: 0,
        serverNow: now,
      );
      expect(cmp, lessThan(0));
    });

    test('elapsed ago uses days after 24 hours', () {
      expect(
        formatLookingForElapsedAgoLabel(const Duration(hours: 158)),
        'Expired 6 days ago',
      );
      expect(
        formatLookingForElapsedAgoLabel(const Duration(hours: 168)),
        'Expired 7 days ago',
      );
      expect(
        formatLookingForElapsedAgoLabel(const Duration(hours: 23)),
        'Expired 23 hours ago',
      );
      expect(
        formatLookingForElapsedAgoLabel(const Duration(minutes: 45)),
        'Expired 45 minutes ago',
      );
      expect(formatLookingForElapsedAgoLabel(Duration.zero), 'Just expired');
    });

    test('dispute and post status labels stay separate when post expired', () {
      final expiredAt = now.subtract(const Duration(hours: 158));
      expect(lookingForDisputeStatusTableLabel('under_review'), 'Under review');
      expect(
        lookingForPostStatusTableLabel(
          disputeStatus: 'under_review',
          expiresAt: expiredAt,
          serverNow: now,
        ),
        'Expired 6 days ago',
      );
    });

    test(
      'overdue open report sorts before newer open report at equal severity',
      () {
        final cmp = compareLookingForReportPriority(
          reasonA: 'spam',
          statusA: 'under_review',
          expiresA: now.add(const Duration(days: 1)),
          createdA: now.subtract(const Duration(hours: 30)),
          openA: 1,
          violationsA: 0,
          reasonB: 'spam',
          statusB: 'under_review',
          expiresB: now.add(const Duration(days: 1)),
          createdB: now.subtract(const Duration(hours: 2)),
          openB: 1,
          violationsB: 0,
          serverNow: now,
        );
        expect(cmp, lessThan(0));
      },
    );
  });
}
