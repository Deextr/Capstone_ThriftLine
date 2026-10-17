import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/auction_checkout_order.dart';

void main() {
  test('order_not_ready maps to actionable buyer copy', () {
    final result = AuctionCheckoutOrderResult.fromRpc({
      'success': false,
      'code': 'order_not_ready',
      'error':
          'We could not prepare your auction order yet. Please try again in a moment.',
    });
    expect(
      buyerFacingAuctionOrderError(result),
      contains('prepare your auction order'),
    );
  });
}
