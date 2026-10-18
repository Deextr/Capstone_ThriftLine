import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/transaction_history_format.dart';

void main() {
  group('transactionHistoryDateGroupHeader', () {
    test('labels today and yesterday', () {
      final now = DateTime(2026, 10, 18, 14, 30);
      expect(
        transactionHistoryDateGroupHeader(
          DateTime(2026, 10, 18, 9),
          now: now,
        ),
        'Today',
      );
      expect(
        transactionHistoryDateGroupHeader(
          DateTime(2026, 10, 17, 9),
          now: now,
        ),
        'Yesterday',
      );
    });
  });

  group('formatTransactionOrderReference', () {
    test('prefixes hash when missing', () {
      expect(formatTransactionOrderReference('TL-99'), '#TL-99');
      expect(formatTransactionOrderReference('#TL-99'), '#TL-99');
    });
  });

  group('sanitizeTransactionProductImageUrl', () {
    test('accepts https and rejects invalid', () {
      expect(
        sanitizeTransactionProductImageUrl('https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
      expect(sanitizeTransactionProductImageUrl('file:///tmp/x.jpg'), isNull);
      expect(sanitizeTransactionProductImageUrl(''), isNull);
    });
  });
}
