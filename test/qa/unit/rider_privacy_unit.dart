import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/rider_privacy.dart';

import '../support/qa_reporter.dart';

void riderPrivacyUnitTests() {
  qaGroup('Rider privacy', () {
    qaUnitTest('maskRiderName keeps first name and last initial', () {
      expect(maskRiderName('pedro santos cruz'), 'pedro C.');
      expect(maskRiderName('Pedro'), 'Pedro');
      expect(maskRiderName(null), 'Rider');
      expect(maskRiderName('   '), 'Rider');
    });

    qaUnitTest('maskRiderPhone hides all but last 4 digits for buyers', () {
      expect(maskRiderPhone('09171234567'), '09••• ••• 4567');
      expect(maskRiderPhone('12'), '09••• ••• ••••');
      expect(maskRiderPhone(null), '09••• ••• ••••');
    });

    qaUnitTest('maskRiderPhone shows prefix and suffix for sellers', () {
      expect(maskRiderPhone('09171234567', sellerView: true), '0917••••567');
      expect(maskRiderPhone('12', sellerView: true), '12');
      expect(maskRiderPhone('12345', sellerView: true), '12345');
    });

    qaUnitTest('formatInspectionRemaining shows hours and padded mins', () {
      final now = DateTime(2026, 10, 4, 12);
      expect(formatInspectionRemaining(null), '—');
      expect(
        formatInspectionRemaining(
          now.add(const Duration(hours: 5, minutes: 7)),
          now: now,
        ),
        '5h 07m',
      );
      expect(
        formatInspectionRemaining(
          now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        'Inspection window ended',
      );
    });
  });
}
