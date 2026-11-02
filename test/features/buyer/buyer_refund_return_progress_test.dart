import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/buyer_order_refund.dart';
import 'package:thriftline/features/buyer/data/buyer_transaction.dart';
import 'package:thriftline/models/return_shipment.dart';

void main() {
  group('buildRefundReturnProgressSteps', () {
    test('manual refund needs GCash before transfer', () {
      final steps = buildRefundReturnProgressSteps(
        refundState: BuyerRefundState.manualRequired,
        gcashSubmitted: false,
      );
      expect(steps.map((s) => s.label), contains('Add your GCash details'));
      expect(
        steps.firstWhere((s) => s.label == 'Add your GCash details').state,
        RefundReturnStepState.current,
      );
    });

    test(
      'combines refund and return without duplicate refund approved rows',
      () {
        final steps = buildRefundReturnProgressSteps(
          refundState: BuyerRefundState.manualRequired,
          gcashSubmitted: true,
          itemReturn: ReturnShipment.fromSupabase({
            'return_id': 'r1',
            'return_required': true,
            'status': 'waiting_for_rider',
          }),
        );
        expect(steps.where((s) => s.label == 'Refund approved').length, 1);
        expect(steps.map((s) => s.label), contains('Return pickup arranged'));
      },
    );
  });
}
