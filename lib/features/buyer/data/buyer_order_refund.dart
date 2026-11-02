import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../models/return_shipment.dart';
import 'buyer_transaction.dart';

/// Optional GCash submit wiring for order/report refund UI.
class RefundGcashFormBindings {
  const RefundGcashFormBindings({
    required this.isSubmitting,
    required this.error,
    required this.clearError,
    required this.submit,
  });

  final bool isSubmitting;
  final String? error;
  final VoidCallback clearError;
  final Future<bool> Function({
    required String accountName,
    required String mobileNumber,
  })
  submit;
}

/// Refund progress for one order (from [get_my_order_refund_status]).
class BuyerOrderRefundInfo {
  const BuyerOrderRefundInfo({
    required this.orderId,
    required this.transaction,
  });

  final String orderId;
  final BuyerTransaction transaction;

  factory BuyerOrderRefundInfo.fromRpc(Map<String, dynamic> map) {
    final txn = BuyerTransaction.fromJson(map);
    return BuyerOrderRefundInfo(
      orderId: map['order_id'] as String? ?? txn.orderId,
      transaction: txn,
    );
  }
}

Future<BuyerOrderRefundInfo?> fetchMyOrderRefundStatus(
  SupabaseService supabase,
  String orderId,
) async {
  final id = orderId.trim();
  if (id.isEmpty) return null;
  try {
    final raw = await supabase.client.rpc(
      'get_my_order_refund_status',
      params: {'p_order_id': id},
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] != true) return null;
    return BuyerOrderRefundInfo.fromRpc(map);
  } catch (e) {
    return null;
  }
}

Future<String?> submitMyRefundGcash({
  required SupabaseService supabase,
  required String escrowId,
  required String accountName,
  required String mobileNumber,
}) async {
  final nameError = validateGcashAccountName(accountName);
  final mobileError = validateGcashMobileNumber(mobileNumber);
  if (nameError != null) return nameError;
  if (mobileError != null) return mobileError;
  try {
    final raw = await supabase.client.rpc(
      'submit_my_refund_gcash',
      params: {
        'p_escrow_id': escrowId,
        'p_account_name': accountName.trim(),
        'p_mobile_number': normalizePhMobileNumber(mobileNumber),
      },
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] != true) {
      return supabaseRpcError(
        map,
        fallback: 'We could not save your GCash details. Try again.',
      );
    }
    return null;
  } catch (_) {
    return 'We could not save your GCash details. Try again.';
  }
}

enum RefundReturnStepState { done, current, upcoming }

class RefundReturnProgressStep {
  const RefundReturnProgressStep({required this.label, required this.state});

  final String label;
  final RefundReturnStepState state;
}

/// One combined refund + physical-return tracker for buyers.
List<RefundReturnProgressStep> buildRefundReturnProgressSteps({
  required BuyerRefundState? refundState,
  required bool gcashSubmitted,
  ReturnShipment? itemReturn,
}) {
  if (refundState == null && itemReturn == null) return const [];

  final steps = <RefundReturnProgressStep>[];
  final refundComplete = buyerRefundStateIsComplete(refundState);
  final returnRequired = itemReturn?.returnRequired == true;

  void addDone(String label) {
    steps.add(
      RefundReturnProgressStep(label: label, state: RefundReturnStepState.done),
    );
  }

  void addCurrent(String label) {
    steps.add(
      RefundReturnProgressStep(
        label: label,
        state: RefundReturnStepState.current,
      ),
    );
  }

  void addUpcoming(String label) {
    steps.add(
      RefundReturnProgressStep(
        label: label,
        state: RefundReturnStepState.upcoming,
      ),
    );
  }

  addDone('Refund approved');

  switch (refundState) {
    case BuyerRefundState.manualRequired:
      if (!gcashSubmitted) {
        addCurrent('Add your GCash details');
      } else if (!refundComplete) {
        addDone('GCash details submitted');
        addCurrent('Waiting for refund transfer');
      }
    case BuyerRefundState.providerPending:
    case BuyerRefundState.awaitingBuyerClaim:
      if (!refundComplete) {
        addCurrent('Refund processing');
      }
    case BuyerRefundState.succeeded:
    case BuyerRefundState.manualCompleted:
    case null:
      break;
  }

  if (refundComplete) {
    addDone(
      refundState == BuyerRefundState.manualCompleted
          ? 'Refund sent to GCash'
          : 'Refund completed',
    );
  } else if (refundState != BuyerRefundState.manualRequired &&
      refundState != BuyerRefundState.providerPending &&
      refundState != BuyerRefundState.awaitingBuyerClaim &&
      refundState != null) {
    addUpcoming('Refund completed');
  }

  if (!returnRequired) return _markLastCurrentIfNeeded(steps);

  final status = itemReturn!.status;
  final returnDone = status == 'returned';
  final returnCancelled = status == 'cancelled_by_admin';

  void addReturnStep(
    String label, {
    required bool done,
    required bool current,
  }) {
    if (done) {
      addDone(label);
    } else if (current) {
      addCurrent(label);
    } else {
      addUpcoming(label);
    }
  }

  final waitingReturn = status == 'waiting_for_rider';
  final pickupArranged = status == 'rider_assigned';
  final inTransit = status == 'picked_up';

  addReturnStep(
    'Return pickup arranged',
    done: pickupArranged || inTransit || returnDone,
    current: waitingReturn,
  );
  addReturnStep(
    'Item picked up from you',
    done: inTransit || returnDone,
    current: pickupArranged,
  );
  addReturnStep(
    'Item received by seller',
    done: returnDone,
    current: inTransit,
  );
  if (returnDone) {
    addDone('Return completed');
  } else if (!returnCancelled && status != 'not_required') {
    addUpcoming('Return completed');
  }

  return _markLastCurrentIfNeeded(steps);
}

List<RefundReturnProgressStep> _markLastCurrentIfNeeded(
  List<RefundReturnProgressStep> steps,
) {
  if (steps.isEmpty) return steps;
  if (steps.any((s) => s.state == RefundReturnStepState.current)) {
    return steps;
  }
  final lastDone = steps.lastIndexWhere(
    (s) => s.state == RefundReturnStepState.done,
  );
  if (lastDone < 0 || lastDone >= steps.length - 1) return steps;
  return [
    for (var i = 0; i < steps.length; i++)
      if (i == lastDone + 1)
        RefundReturnProgressStep(
          label: steps[i].label,
          state: RefundReturnStepState.current,
        )
      else
        steps[i],
  ];
}

bool orderShowsRefundReturnProgress(OrderModel order) {
  return order.isRefundedSale || order.itemReturn?.returnRequired == true;
}
