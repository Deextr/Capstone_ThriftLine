import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

class AuctionCheckoutOrderResult {
  const AuctionCheckoutOrderResult({
    required this.success,
    this.orderId,
    this.error,
    this.code,
  });

  final bool success;
  final String? orderId;
  final String? error;
  final String? code;

  factory AuctionCheckoutOrderResult.fromRpc(dynamic raw) {
    final map = supabaseRpcMap(raw);
    if (map == null) {
      return const AuctionCheckoutOrderResult(
        success: false,
        error: 'Unable to prepare your order. Please try again.',
      );
    }
    final orderId = map['order_id']?.toString().trim();
    return AuctionCheckoutOrderResult(
      success: map['success'] == true,
      orderId: orderId != null && orderId.isNotEmpty ? orderId : null,
      error: supabaseRpcError(map, fallback: ''),
      code: map['code']?.toString(),
    );
  }
}

String buyerFacingAuctionOrderError(AuctionCheckoutOrderResult result) {
  if (result.success && result.orderId != null) return '';
  switch (result.code) {
    case 'payment_window_closed':
      return 'Your payment window for this auction has ended.';
    case 'not_eligible':
      return 'You are not eligible to pay for this auction.';
    case 'no_winner':
      return 'This auction does not have a winner yet. Pull to refresh.';
    case 'order_not_ready':
      return result.error?.isNotEmpty == true
          ? result.error!
          : 'Your pending order is not ready yet. Please wait a moment and try again.';
    default:
      return result.error?.isNotEmpty == true
          ? result.error!
          : 'Unable to prepare your order. Please try again.';
  }
}

/// Idempotent: settle if needed and return the buyer's pending auction order id.
Future<AuctionCheckoutOrderResult> ensureMyAuctionOrder(
  SupabaseService supabase,
  String auctionId,
) async {
  if (auctionId.isEmpty) {
    return const AuctionCheckoutOrderResult(
      success: false,
      error: 'Auction not found.',
    );
  }
  try {
    const retryDelaysMs = [200, 400, 800, 1200];
    for (var attempt = 0; attempt <= retryDelaysMs.length; attempt++) {
      final raw = await supabase.client.rpc(
        'ensure_my_auction_order',
        params: {'p_auction_id': auctionId},
      );
      final result = AuctionCheckoutOrderResult.fromRpc(raw);
      if (result.success && result.orderId != null) {
        return result;
      }
      if (result.code != 'order_not_ready' || attempt >= retryDelaysMs.length) {
        return result;
      }
      await Future<void>.delayed(
        Duration(milliseconds: retryDelaysMs[attempt]),
      );
    }
    return const AuctionCheckoutOrderResult(
      success: false,
      code: 'order_not_ready',
      error:
          'Your pending order is not ready yet. Please wait a moment and try again.',
    );
  } catch (e) {
    return AuctionCheckoutOrderResult(
      success: false,
      error: 'Unable to prepare your order. Please try again.',
    );
  }
}
