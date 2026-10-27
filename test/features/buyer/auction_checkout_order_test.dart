import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/auction_checkout_order.dart';

void main() {
  group('AuctionCheckoutOrderResult', () {
    test('parses success with order_id', () {
      final result = AuctionCheckoutOrderResult.fromRpc({
        'success': true,
        'order_id': 'ord-1',
      });
      expect(result.success, isTrue);
      expect(result.orderId, 'ord-1');
    });

    test('maps payment window closed code', () {
      const result = AuctionCheckoutOrderResult(
        success: false,
        code: 'payment_window_closed',
      );
      expect(
        buyerFacingAuctionOrderError(result),
        contains('payment window'),
      );
    });

    test('maps order_not_ready server message', () {
      final result = AuctionCheckoutOrderResult.fromRpc({
        'success': false,
        'code': 'order_not_ready',
        'error':
            'Your pending order is not ready yet. We are still preparing it — please wait a moment and try again.',
      });
      expect(result.code, 'order_not_ready');
      expect(
        buyerFacingAuctionOrderError(result),
        contains('pending order is not ready'),
      );
    });
  });
}
