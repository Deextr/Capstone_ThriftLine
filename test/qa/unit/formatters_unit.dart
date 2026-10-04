import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';

import '../support/qa_reporter.dart';

void formattersUnitTests() {
  qaGroup('Formatters', () {
    qaUnitTest('formatCurrency uses peso sign, grouping, no decimals', () {
      final text = formatCurrency(1500);
      expect(text, contains('₱'));
      expect(text, contains('1,500'));
      expect(text, isNot(contains('.')));
    });

    qaUnitTest('formatCentavos converts centavos to pesos', () {
      expect(formatCentavos(125000), formatCurrency(1250));
      expect(formatCentavos(125000), contains('1,250'));
    });

    qaUnitTest('shortPersonName shows first name + last initial', () {
      expect(shortPersonName('Dexter Ramos'), 'Dexter R.');
      expect(shortPersonName('juan dela cruz'), 'juan C.');
      expect(shortPersonName('Maria'), 'Maria');
    });

    qaUnitTest('shortPersonName falls back for empty names', () {
      expect(shortPersonName(null), 'Buyer');
      expect(shortPersonName('   '), 'Buyer');
      expect(shortPersonName(null, fallback: 'Seller'), 'Seller');
    });

    qaUnitTest('formatCompactDate returns "today" or a short date', () {
      final now = DateTime(2026, 10, 4, 15);
      expect(formatCompactDate(DateTime(2026, 10, 4, 8), now: now), 'today');
      expect(formatCompactDate(DateTime(2026, 9, 28), now: now), 'Sep 28');
    });

    qaUnitTest('formatFullDate includes the year', () {
      expect(formatFullDate(DateTime(2026, 1, 5)), 'Jan 5, 2026');
    });

    qaUnitTest('formatRelativeTime buckets by minutes, hours, days', () {
      final now = DateTime.now();
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 20))),
        'Just now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5))),
        '5m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2))),
        '2d ago',
      );
    });

    qaGroup('formatPaymentDeadline', () {
      final due = DateTime(2026, 10, 4, 18);

      qaUnitTest('shows hours and minutes left', () {
        expect(
          formatPaymentDeadline(due, now: DateTime(2026, 10, 4, 15, 30)),
          'Pay by Oct 4, 6:00 PM (2 h 30 m left)',
        );
      });

      qaUnitTest('shows minutes and seconds under one hour', () {
        expect(
          formatPaymentDeadline(due, now: DateTime(2026, 10, 4, 17, 54, 50)),
          'Pay by Oct 4, 6:00 PM (5 m 10 s left)',
        );
      });

      qaUnitTest('shows seconds only under one minute', () {
        expect(
          formatPaymentDeadline(due, now: DateTime(2026, 10, 4, 17, 59, 15)),
          'Pay by Oct 4, 6:00 PM (45 s left)',
        );
      });

      qaUnitTest('reports an ended window once past due', () {
        expect(
          formatPaymentDeadline(due, now: DateTime(2026, 10, 4, 18, 1)),
          'Payment window ended Oct 4, 6:00 PM',
        );
      });
    });

    qaGroup('countdowns', () {
      qaUnitTest('formatCountdown pads hours/minutes and adds days', () {
        expect(formatCountdown(const Duration(minutes: 7)), '00:07');
        expect(
          formatCountdown(const Duration(days: 1, hours: 3, minutes: 7)),
          '1d 03:07',
        );
        expect(formatCountdown(Duration.zero), 'Ended');
      });

      qaUnitTest('formatReadableCountdown uses labelled units', () {
        expect(
          formatReadableCountdown(
            const Duration(days: 2, hours: 5, minutes: 9),
          ),
          '2d 5h 9m',
        );
        expect(
          formatReadableCountdown(const Duration(hours: 4, minutes: 0)),
          '4h 0m',
        );
        expect(formatReadableCountdown(const Duration(seconds: 45)), '45s');
        expect(
          formatReadableCountdown(const Duration(seconds: -1)),
          'Ended',
        );
      });
    });
  });
}
