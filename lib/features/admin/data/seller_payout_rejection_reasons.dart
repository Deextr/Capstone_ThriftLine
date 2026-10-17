import '../domain/admin_seller_payout.dart';

/// Admin-selected reasons when rejecting a seller GCash payout request.
/// The resolved label is stored in [rejection_reason] and shown to the seller.
class SellerPayoutRejectReason {
  const SellerPayoutRejectReason({required this.id, required this.label});

  final String id;
  final String label;

  bool get isOther => id == kSellerPayoutRejectOtherId;
}

const String kSellerPayoutRejectOtherId = 'other';

const List<SellerPayoutRejectReason> kSellerPayoutRejectReasons = [
  SellerPayoutRejectReason(
    id: 'invalid_gcash',
    label: 'GCash mobile number or account name looks incorrect or invalid.',
  ),
  SellerPayoutRejectReason(
    id: 'incomplete_details',
    label: 'GCash payout details on this request are incomplete.',
  ),
  SellerPayoutRejectReason(
    id: 'name_mismatch',
    label:
        'GCash account name does not match the seller\'s registered details.',
  ),
  SellerPayoutRejectReason(
    id: 'missing_gcash',
    label:
        'No valid GCash destination is saved. Update GCash in the app and request again.',
  ),
  SellerPayoutRejectReason(
    id: 'requirements_not_met',
    label: 'This payout request does not meet ThriftLine payout requirements.',
  ),
  SellerPayoutRejectReason(
    id: kSellerPayoutRejectOtherId,
    label: 'Other reason',
  ),
];

/// Seller-facing message stored on the payout row.
String? sellerPayoutRejectionReasonMessage({
  required String? reasonId,
  String? otherDetail,
}) {
  if (reasonId == null || reasonId.isEmpty) return null;
  if (reasonId == kSellerPayoutRejectOtherId) {
    final detail = otherDetail?.trim() ?? '';
    return detail.isEmpty ? null : detail;
  }
  for (final reason in kSellerPayoutRejectReasons) {
    if (reason.id == reasonId) return reason.label;
  }
  return null;
}

/// Validates admin rejection input before calling the reject RPC.
String? validatePayoutRejectionSelection({
  required String? reasonId,
  String? otherDetail,
}) {
  if (reasonId == null || reasonId.isEmpty) {
    return 'Select a rejection reason.';
  }
  final message = sellerPayoutRejectionReasonMessage(
    reasonId: reasonId,
    otherDetail: otherDetail,
  );
  if (message == null) {
    if (reasonId == kSellerPayoutRejectOtherId) {
      return 'Add a short explanation (at least 5 characters).';
    }
    return 'Select a rejection reason.';
  }
  return validateRejectionReason(message);
}
