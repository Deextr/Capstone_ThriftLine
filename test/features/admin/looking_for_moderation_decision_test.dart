import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/looking_for_moderation_decision_content.dart';

void main() {
  group('Looking For moderation decisions', () {
    test('maps UI slugs to review_looking_for_report RPC values', () {
      expect(
        lookingForDecisionToRpc(kLookingForDecisionRemovePost),
        'resolved',
      );
      expect(
        lookingForDecisionToRpc(kLookingForDecisionDismissReport),
        'dismissed',
      );
      expect(kLookingForDisputeDecisionOptions.length, 2);
    });

    test('remove post requires violation confirmation', () {
      expect(
        lookingForDecisionRequiresViolation(kLookingForDecisionRemovePost),
        isTrue,
      );
      expect(
        lookingForDecisionRequiresViolation(kLookingForDecisionDismissReport),
        isFalse,
      );
    });

    test('reason templates are scoped per decision', () {
      final remove = lookingForDecisionReasonTemplates(
        kLookingForDecisionRemovePost,
      );
      final dismiss = lookingForDecisionReasonTemplates(
        kLookingForDecisionDismissReport,
      );
      expect(remove.any((t) => t.id == 'spam'), isTrue);
      expect(dismiss.any((t) => t.id == 'no_violation'), isTrue);
      expect(remove.any((t) => t.id == 'no_violation'), isFalse);
      expect(dismiss.any((t) => t.id == 'insufficient_evidence'), isFalse);
    });
  });
}
