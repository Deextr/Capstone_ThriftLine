/// Buyer GCash details and the manual transfer record for one refund.
class AdminRefundDetails {
  const AdminRefundDetails({
    this.transferLinkExpiresAt,
    this.hasTransferLink = false,
    this.gcashAccountName,
    this.gcashMobileNumber,
    this.gcashSubmittedAt,
    this.manualAmountCentavos,
    this.manualReference,
    this.manualSentAt,
    this.manualEvidencePath,
    this.manualNote,
    this.manualRecordedAt,
  });

  final DateTime? transferLinkExpiresAt;
  final bool hasTransferLink;
  final String? gcashAccountName;
  final String? gcashMobileNumber;
  final DateTime? gcashSubmittedAt;
  final int? manualAmountCentavos;
  final String? manualReference;
  final DateTime? manualSentAt;
  final String? manualEvidencePath;
  final String? manualNote;
  final DateTime? manualRecordedAt;

  bool get buyerSentGcash =>
      (gcashAccountName?.isNotEmpty ?? false) &&
      (gcashMobileNumber?.isNotEmpty ?? false);

  bool get hasManualRecord => manualReference?.isNotEmpty ?? false;

  factory AdminRefundDetails.fromMap(Map<String, dynamic> map) {
    final link = (map['transfer_link'] as String?)?.trim() ?? '';
    return AdminRefundDetails(
      transferLinkExpiresAt: _time(map['transfer_link_expires_at']),
      hasTransferLink: link.isNotEmpty,
      gcashAccountName: _text(map['gcash_account_name']),
      gcashMobileNumber: _text(map['gcash_mobile_number']),
      gcashSubmittedAt: _time(map['gcash_submitted_at']),
      manualAmountCentavos: (map['manual_amount_centavos'] as num?)?.toInt(),
      manualReference: _text(map['manual_reference']),
      manualSentAt: _time(map['manual_sent_at']),
      manualEvidencePath: _text(map['manual_evidence_path']),
      manualNote: _text(map['manual_note']),
      manualRecordedAt: _time(map['manual_recorded_at']),
    );
  }
}

/// One row of the PayMongo refund audit trail.
class AdminRefundAttempt {
  const AdminRefundAttempt({
    required this.createdAt,
    required this.source,
    required this.action,
    required this.outcome,
    this.paymongoRefundId,
    this.httpStatus,
    this.providerStatus,
    this.errorCode,
  });

  final DateTime createdAt;
  final String source;
  final String action;
  final String outcome;
  final String? paymongoRefundId;
  final int? httpStatus;
  final String? providerStatus;
  final String? errorCode;

  factory AdminRefundAttempt.fromMap(Map<String, dynamic> map) {
    return AdminRefundAttempt(
      createdAt:
          _time(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      source: _text(map['source']) ?? '',
      action: _text(map['action']) ?? '',
      outcome: _text(map['outcome']) ?? '',
      paymongoRefundId: _text(map['paymongo_refund_id']),
      httpStatus: (map['http_status'] as num?)?.toInt(),
      providerStatus: _text(map['provider_status']),
      errorCode: _text(map['error_code']),
    );
  }

  String get title {
    final what = switch (action) {
      'create' => 'Refund request sent to PayMongo',
      'adopt' => 'Existing PayMongo refund found',
      'lookup' => 'Checked PayMongo for a refund',
      'retrieve' => 'Checked PayMongo refund status',
      'webhook' => 'PayMongo sent an update',
      _ => 'PayMongo refund activity',
    };
    return '$what · ${adminRefundOutcomeLabel(outcome)}';
  }

  String get detail {
    final parts = <String>[
      adminRefundSourceLabel(source),
      if (providerStatus != null) 'PayMongo: $providerStatus',
      if (httpStatus != null) 'HTTP $httpStatus',
      if (errorCode != null) errorCode!,
    ];
    return parts.join(' · ');
  }
}

String adminRefundOutcomeLabel(String outcome) => switch (outcome) {
  'accepted' => 'accepted',
  'rejected' => 'refused',
  'unknown' => 'no confirmed answer',
  'updated' => 'updated',
  'not_found' => 'no refund found',
  _ => outcome.isEmpty ? 'recorded' : outcome,
};

String adminRefundSourceLabel(String source) => switch (source) {
  'admin_dispute' => 'Dispute decision',
  'fulfillment_sla' => 'Seller missed shipping deadline',
  'admin_retry' => 'Admin',
  'reconcile' => 'Automatic check',
  'webhook' => 'PayMongo webhook',
  _ => source.isEmpty ? 'System' : source,
};

/// Result of a `reconcile-refund` call, in words an admin can act on.
class AdminRefundActionResult {
  const AdminRefundActionResult({
    required this.success,
    required this.message,
    this.refundState,
  });

  final bool success;
  final String message;
  final String? refundState;
}

AdminRefundActionResult adminRefundActionResultFromMap(
  Map<String, dynamic>? map, {
  required String action,
}) {
  if (map == null) {
    return const AdminRefundActionResult(
      success: false,
      message: 'PayMongo could not be reached. Nothing was changed.',
    );
  }
  final state = (map['refund_state'] as String?)?.trim();
  final error = (map['error'] as String?)?.trim();
  if (map['success'] != true) {
    return AdminRefundActionResult(
      success: false,
      refundState: state,
      message: error?.isNotEmpty == true
          ? error!
          : 'Could not update this refund. Try again.',
    );
  }

  final String message;
  if (map['verified_no_refund'] == true) {
    message =
        'PayMongo has no refund for this payment. Send a manual GCash refund '
        'and record it here.';
  } else if (map['nothing_to_check'] == true) {
    message = 'There is nothing to check with PayMongo for this refund.';
  } else if (map['rejected'] == true) {
    final code = (map['error_code'] as String?)?.trim();
    message =
        'PayMongo refused the refund${code == null || code.isEmpty ? '' : ' ($code)'}. '
        'Send a manual GCash refund instead.';
  } else if (map['adopted'] == true || map['adopted_refund_id'] != null) {
    message =
        'PayMongo already had a refund for this payment. ThriftLine is now '
        'tracking it.';
  } else {
    message = switch (state) {
      'succeeded' => 'PayMongo confirmed the refund is complete.',
      'awaiting_buyer_claim' =>
        'PayMongo sent the buyer a claim link. Waiting for the buyer.',
      'provider_pending' =>
        action == 'retry'
            ? 'PayMongo accepted the refund. It is processing.'
            : 'PayMongo is still processing this refund.',
      'manual_required' =>
        'PayMongo did not return this payment. A manual GCash refund is needed.',
      _ => 'Refund updated.',
    };
  }
  return AdminRefundActionResult(
    success: true,
    refundState: state,
    message: message,
  );
}

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

DateTime? _time(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
