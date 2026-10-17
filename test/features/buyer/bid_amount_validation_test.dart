import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/domain/bid_amount_validation.dart';

void main() {
  group('bidAmountValidationError', () {
    const minBid = 500.0;

    test('rejects empty input', () {
      expect(
        bidAmountValidationError(rawInput: '', minimumBid: minBid),
        isNotNull,
      );
    });

    test('rejects alphabetic input', () {
      expect(
        bidAmountValidationError(rawInput: 'abc', minimumBid: minBid),
        isNotNull,
      );
    });

    test('rejects zero and negative bids', () {
      expect(
        bidAmountValidationError(rawInput: '0', minimumBid: minBid),
        isNotNull,
      );
      expect(
        bidAmountValidationError(rawInput: '-10', minimumBid: minBid),
        isNotNull,
      );
    });

    test('rejects bids below minimum', () {
      expect(
        bidAmountValidationError(rawInput: '499', minimumBid: minBid),
        contains('at least'),
      );
    });

    test('accepts valid bids at or above minimum', () {
      expect(
        bidAmountValidationError(rawInput: '500', minimumBid: minBid),
        isNull,
      );
      expect(
        bidAmountValidationError(rawInput: '750', minimumBid: minBid),
        isNull,
      );
    });
  });
}
