/// Common reasons an admin can send when a Become a Seller application fails.
/// The chosen label is stored as [rejection_reason] and shown to the applicant.
class SellerApplicationRejectReason {
  const SellerApplicationRejectReason({required this.id, required this.label});

  final String id;
  final String label;

  bool get isOther => id == kSellerApplicationRejectOtherId;
}

const String kSellerApplicationRejectOtherId = 'other';

const List<SellerApplicationRejectReason> kSellerApplicationRejectReasons = [
  SellerApplicationRejectReason(
    id: 'id_unreadable',
    label: 'Government ID is blurry, cropped, or unreadable.',
  ),
  SellerApplicationRejectReason(
    id: 'id_wrong_side',
    label: 'ID front or back is missing, or the wrong side was uploaded.',
  ),
  SellerApplicationRejectReason(
    id: 'id_type_mismatch',
    label: 'The uploaded ID does not match the ID type you selected.',
  ),
  SellerApplicationRejectReason(
    id: 'id_not_original',
    label:
        'ID photos look like a screenshot, photocopy, or another person\'s ID.',
  ),
  SellerApplicationRejectReason(
    id: 'name_mismatch',
    label: 'The name on the ID does not match the shop or profile name.',
  ),
  SellerApplicationRejectReason(
    id: 'face_mismatch',
    label: 'The face photo does not match the government ID.',
  ),
  SellerApplicationRejectReason(
    id: 'liveness_failed',
    label:
        'Liveness checks failed. Retake the look-left, look-right, and blink steps.',
  ),
  SellerApplicationRejectReason(
    id: 'shop_name',
    label:
        'Shop name is incomplete, misleading, or does not look like a real shop.',
  ),
  SellerApplicationRejectReason(
    id: 'address_invalid',
    label: 'Pickup address is incomplete or is not a valid Davao City address.',
  ),
  SellerApplicationRejectReason(
    id: 'underage',
    label: 'The submitted ID shows the applicant is under 18.',
  ),
  SellerApplicationRejectReason(
    id: kSellerApplicationRejectOtherId,
    label: 'Others',
  ),
];

/// Applicant-facing message stored on the verification row.
String? sellerRejectionReasonMessage({
  required String? reasonId,
  String? otherDetail,
}) {
  if (reasonId == null || reasonId.isEmpty) return null;
  if (reasonId == kSellerApplicationRejectOtherId) {
    final detail = otherDetail?.trim() ?? '';
    return detail.isEmpty ? null : detail;
  }
  for (final reason in kSellerApplicationRejectReasons) {
    if (reason.id == reasonId) return reason.label;
  }
  return null;
}
