import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_report_decision_content.dart';
import 'package:thriftline/features/admin/presentation/widgets/community_dispute_decision_cards.dart';

void main() {
  group('community dispute decision UI helpers', () {
    test('action labels match modal copy', () {
      expect(communityDisputeModalActionLabel('resolved'), 'Resolve Dispute');
      expect(
        communityDisputeModalActionLabel('needs_more_evidence'),
        'Send Evidence Request',
      );
      expect(communityDisputeModalActionLabel('dismissed'), 'Dismiss Dispute');
    });

    test('templates are filtered per decision', () {
      final resolved = adminCommunityDecisionTemplatesFor('resolved');
      expect(
        resolved.every((t) => t.id == 'resolved' || t.id == 'custom'),
        isTrue,
      );

      final evidence = adminCommunityDecisionTemplatesFor(
        'needs_more_evidence',
      );
      expect(evidence.any((t) => t.id == 'insufficient_evidence'), isTrue);
      expect(
        evidence.where((t) => t.label == 'Additional evidence required').length,
        1,
      );
      expect(evidence.any((t) => t.id == 'dismissed'), isFalse);
    });
  });

  group('CommunityDisputeDecisionCardGroup', () {
    testWidgets('renders three equal-width cards in a row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 720,
                child: CommunityDisputeDecisionCardGroup(
                  selectedValue: 'resolved',
                  onSelected: (_) {},
                  options: kCommunityDisputeDecisionOptions,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CommunityDisputeDecisionCard), findsNWidgets(3));

      final cards = find.byType(CommunityDisputeDecisionCard);
      final w0 = tester.getSize(cards.at(0)).width;
      final w1 = tester.getSize(cards.at(1)).width;
      final w2 = tester.getSize(cards.at(2)).width;
      expect(w0, closeTo(w1, 1));
      expect(w2, closeTo(w1, 1));
    });
  });
}
