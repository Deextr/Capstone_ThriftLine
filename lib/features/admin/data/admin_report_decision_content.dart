/// Predefined admin response templates and evidence types for report decisions.

class AdminResponseTemplate {
  const AdminResponseTemplate({
    required this.id,
    required this.label,
    required this.message,
  });

  final String id;
  final String label;
  final String message;
}

const List<AdminResponseTemplate> kAdminOrderCloseTemplates = [
  AdminResponseTemplate(
    id: 'refund_approved',
    label: 'Refund approved',
    message:
        'We reviewed your order report and approved a refund. The refund will be processed according to our payment policy.',
  ),
  AdminResponseTemplate(
    id: 'payment_released',
    label: 'Payment released to seller',
    message:
        'We reviewed your order report and released the held payment to the seller. This case is now closed.',
  ),
  AdminResponseTemplate(
    id: 'case_resolved',
    label: 'Case resolved',
    message:
        'Thank you for your report. We completed our review and closed this case.',
  ),
  AdminResponseTemplate(
    id: 'no_violation',
    label: 'No violation found',
    message:
        'We reviewed the order and available evidence. We did not find a policy violation based on the information provided.',
  ),
  AdminResponseTemplate(
    id: 'violation_confirmed',
    label: 'Violation confirmed',
    message:
        'We confirmed a policy violation related to this order. Appropriate action has been taken.',
  ),
  AdminResponseTemplate(
    id: 'custom',
    label: 'Write custom message',
    message: '',
  ),
];

const List<AdminResponseTemplate> kAdminEvidenceRequestTemplates = [
  AdminResponseTemplate(
    id: 'insufficient_evidence',
    label: 'Insufficient evidence',
    message:
        'After reviewing your report, we do not have enough evidence to make a final decision yet.',
  ),
  AdminResponseTemplate(
    id: 'additional_evidence',
    label: 'Additional evidence required',
    message:
        'We need more supporting evidence before we can continue investigating this report.',
  ),
];

const List<AdminResponseTemplate> kAdminCommunityDecisionTemplates = [
  AdminResponseTemplate(
    id: 'resolved',
    label: 'Case resolved',
    message:
        'Thank you for helping keep ThriftLine safe. We reviewed your report and took appropriate action.',
  ),
  AdminResponseTemplate(
    id: 'dismissed',
    label: 'Report rejected',
    message:
        'We reviewed your report and did not find a policy violation based on the information provided.',
  ),
  AdminResponseTemplate(
    id: 'needs_more_evidence',
    label: 'Additional evidence required',
    message:
        'We need additional evidence before we can complete our review. Please submit the requested details.',
  ),
  AdminResponseTemplate(
    id: 'insufficient_evidence',
    label: 'Insufficient evidence',
    message:
        'We currently do not have enough evidence to make a final decision. Please provide clearer supporting proof.',
  ),
  AdminResponseTemplate(
    id: 'custom',
    label: 'Write custom message',
    message: '',
  ),
];

class AdminEvidenceTypeOption {
  const AdminEvidenceTypeOption({required this.id, required this.label});

  final String id;
  final String label;
}

const List<AdminEvidenceTypeOption> kAdminEvidenceTypeOptions = [
  AdminEvidenceTypeOption(id: 'product_photos', label: 'Product photos'),
  AdminEvidenceTypeOption(id: 'unboxing_photos', label: 'Unboxing photos'),
  AdminEvidenceTypeOption(id: 'unboxing_video', label: 'Unboxing video'),
  AdminEvidenceTypeOption(id: 'packaging_photos', label: 'Packaging photos'),
  AdminEvidenceTypeOption(id: 'delivery_receipt', label: 'Delivery receipt'),
  AdminEvidenceTypeOption(id: 'payment_receipt', label: 'Payment receipt'),
  AdminEvidenceTypeOption(
    id: 'conversation_screenshot',
    label: 'Screenshot of conversation',
  ),
  AdminEvidenceTypeOption(
    id: 'product_condition',
    label: 'Product condition photos',
  ),
  AdminEvidenceTypeOption(
    id: 'courier_tracking',
    label: 'Courier tracking information',
  ),
  AdminEvidenceTypeOption(id: 'proof_shipment', label: 'Proof of shipment'),
  AdminEvidenceTypeOption(id: 'proof_delivery', label: 'Proof of delivery'),
  AdminEvidenceTypeOption(id: 'order_screenshots', label: 'Order screenshots'),
  AdminEvidenceTypeOption(
    id: 'transaction_details',
    label: 'Additional transaction details',
  ),
  AdminEvidenceTypeOption(
    id: 'identity_verification',
    label: 'Identity verification',
  ),
  AdminEvidenceTypeOption(id: 'other', label: 'Other supporting evidence'),
];

String formatEvidenceList(Iterable<String> labels) {
  final list = labels.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return list.first;
  if (list.length == 2) return '${list[0]} and ${list[1]}';
  return '${list.sublist(0, list.length - 1).join(', ')}, and ${list.last}';
}

String buildEvidenceRequestInstruction({
  required List<String> selectedTypeLabels,
  String? customDetail,
  String? intro,
}) {
  final parts = <String>[...selectedTypeLabels];
  final custom = customDetail?.trim();
  if (custom != null && custom.isNotEmpty) {
    parts.add(custom);
  }
  final formatted = formatEvidenceList(parts);
  if (formatted.isEmpty) return '';
  final lead = intro?.trim().isNotEmpty == true
      ? intro!.trim()
      : 'Please provide the following evidence to continue the investigation';
  final suffix = formatted.endsWith('.') ? '' : '.';
  return '$lead: $formatted$suffix';
}

/// Maps UI target to RPC party (`reporter`, `buyer`, `seller`).
enum AdminEvidenceRequestTarget { reporter, reportedUser }

String adminEvidencePartyApiValue({
  required AdminEvidenceRequestTarget target,
  required String reporterId,
  required String reportedUserId,
  required String? orderBuyerId,
  required String? orderSellerId,
}) {
  if (target == AdminEvidenceRequestTarget.reporter) {
    return 'reporter';
  }
  if (orderBuyerId != null &&
      orderSellerId != null &&
      reportedUserId == orderBuyerId) {
    return 'buyer';
  }
  if (orderBuyerId != null &&
      orderSellerId != null &&
      reportedUserId == orderSellerId) {
    return 'seller';
  }
  if (reporterId == orderBuyerId) {
    return 'seller';
  }
  return 'buyer';
}
