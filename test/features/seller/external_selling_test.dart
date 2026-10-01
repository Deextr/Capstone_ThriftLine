import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/external_selling.dart';

ExternalTransactionDraft _draft({
  List<ExternalEvidenceKind> kinds = const [
    ExternalEvidenceKind.conversation,
    ExternalEvidenceKind.payment,
  ],
  DateTime? date,
  String item = 'Vintage shirt',
  double? amount = 850,
  String? url,
}) {
  return ExternalTransactionDraft(
    localId: '1',
    platform: ExternalPlatform.facebookMarketplace,
    approximateDate: date ?? DateTime(2026, 8, 12),
    itemName: item,
    amount: amount,
    listingUrl: url,
    evidence: [
      for (final kind in kinds)
        ExternalEvidenceDraft(kind: kind, bytes: Uint8List.fromList([1, 2, 3])),
    ],
  );
}

void main() {
  test('skipping history is valid and does not require a claimed range', () {
    expect(
      validateExternalHistory(transactions: const [], claimedRange: null),
      isNull,
    );
  });

  test('more than 10 transactions is rejected', () {
    final transactions = List.generate(11, (index) {
      return ExternalTransactionDraft(
        localId: '$index',
        platform: ExternalPlatform.instagram,
        approximateDate: DateTime(2024, 1, 1),
        itemName: 'Item $index',
        evidence: _draft().evidence,
      );
    });
    expect(
      validateExternalHistory(
        transactions: transactions,
        claimedRange: ClaimedSellingRange.aboveFifty,
        today: DateTime(2026, 9, 30),
      ),
      contains('10'),
    );
  });

  test('a claimed range is required only when transactions are added', () {
    expect(
      validateExternalHistory(
        transactions: [_draft()],
        claimedRange: null,
        today: DateTime(2026, 9, 30),
      ),
      contains('approximate'),
    );
  });

  test('one photo or two of the same kind cannot be submitted', () {
    expect(
      validateExternalTransaction(
        _draft(kinds: [ExternalEvidenceKind.conversation]),
        today: DateTime(2026, 9, 30),
      ),
      contains('two'),
    );
    expect(
      validateExternalTransaction(
        _draft(
          kinds: [ExternalEvidenceKind.payment, ExternalEvidenceKind.payment],
        ),
        today: DateTime(2026, 9, 30),
      ),
      contains('different'),
    );
  });

  test('conversation plus payment is acceptable', () {
    expect(
      validateExternalTransaction(_draft(), today: DateTime(2026, 9, 30)),
      isNull,
    );
    expect(
      validateExternalHistory(
        transactions: [_draft()],
        claimedRange: ClaimedSellingRange.aboveFifty,
        today: DateTime(2026, 9, 30),
      ),
      isNull,
    );
  });

  test('a future date is rejected', () {
    expect(
      validateExternalTransaction(
        _draft(date: DateTime(2026, 10, 2)),
        today: DateTime(2026, 9, 30),
      ),
      contains('future'),
    );
  });
}
