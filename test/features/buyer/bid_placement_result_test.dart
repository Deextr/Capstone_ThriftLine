import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/supabase_rpc.dart';
import 'package:thriftline/features/buyer/domain/bid_placement_result.dart';

void main() {
  group('BidPlacementResult.fromRpc', () {
    test('success when rpc success true', () {
      final result = BidPlacementResult.fromRpc({'success': true});
      expect(result.isSuccess, isTrue);
    });

    test('maps phone verification code', () {
      final result = BidPlacementResult.fromRpc({
        'success': false,
        'code': 'phone_verification_required',
        'error': 'Verify your phone number to place a bid.',
      });
      expect(result.isSuccess, isFalse);
      expect(result.code, 'phone_verification_required');
    });

    test('maps bid risk rejection', () {
      final result = BidPlacementResult.fromRpc({
        'success': false,
        'code': 'bid_risk_rejected',
        'error': 'This bid could not be placed.',
      });
      expect(result.code, 'bid_risk_rejected');
    });
  });

  group('supabaseRpcCode', () {
    test('reads code field', () {
      expect(
        supabaseRpcCode({'success': false, 'code': 'bid_risk_rejected'}),
        'bid_risk_rejected',
      );
    });
  });
}
