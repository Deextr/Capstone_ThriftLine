import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/auction_checkout_order.dart';

void main() {
  test('order_not_ready maps to actionable buyer copy', () {
    final result = AuctionCheckoutOrderResult.fromRpc({
      'success': false,
      'code': 'order_not_ready',
      'error':
          'Your pending order is not ready yet. We are still preparing it — please wait a moment and try again.',
    });
    expect(
      buyerFacingAuctionOrderError(result),
      contains('pending order is not ready'),
    );
  });
}
