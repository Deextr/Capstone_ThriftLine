import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/auction_relist_feedback.dart';

void main() {
  test('maps rpc codes to seller-friendly copy', () {
    expect(
      auctionRelistMessageFromRpc(code: 'auction_still_active'),
      contains('Auction still active'),
    );
    expect(
      auctionRelistMessageFromRpc(code: 'awaiting_winner_payment'),
      contains('Awaiting winner payment'),
    );
    expect(
      auctionRelistMessageFromRpc(
        code: 'custom',
        error: 'Server-specific detail.',
      ),
      'Server-specific detail.',
    );
  });
}
