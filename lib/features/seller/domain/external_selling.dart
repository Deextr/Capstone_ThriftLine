import 'dart:typed_data';

/// Self-declared history. It is stored for the admin and never used as the
/// Successful Transactions score.
enum ClaimedSellingRange {
  oneToTen('1_10', '1–10 transactions'),
  elevenToTwenty('11_20', '11–20 transactions'),
  twentyOneToThirty('21_30', '21–30 transactions'),
  thirtyOneToFifty('31_50', '31–50 transactions'),
  aboveFifty('above_50', 'Above 50 transactions');

  const ClaimedSellingRange(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static ClaimedSellingRange? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    for (final range in ClaimedSellingRange.values) {
      if (range.storageValue == value) return range;
    }
    return null;
  }
}

enum ExternalPlatform {
  facebookMarketplace('facebook_marketplace', 'Facebook Marketplace'),
  facebookGroup('facebook_group', 'Facebook Group'),
  instagram('instagram', 'Instagram'),
  other('other', 'Other');

  const ExternalPlatform(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static ExternalPlatform? tryParse(String? value) {
    for (final platform in ExternalPlatform.values) {
      if (platform.storageValue == value) return platform;
    }
    return null;
  }
}

enum ExternalEvidenceKind {
  conversation('conversation', 'Conversation'),
  payment('payment', 'Payment proof'),
  delivery('delivery', 'Delivery receipt'),
  courier('courier', 'Courier confirmation'),
  meetup('meetup', 'Meetup confirmation'),
  acknowledgement('acknowledgement', 'Buyer acknowledgement'),
  feedback('feedback', 'Previous buyer feedback'),
  listing('listing', 'Original listing');

  const ExternalEvidenceKind(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static ExternalEvidenceKind? tryParse(String? value) {
    for (final kind in ExternalEvidenceKind.values) {
      if (kind.storageValue == value) return kind;
    }
    return null;
  }
}

enum ExternalReviewStatus {
  pending('pending', 'Pending review'),
  verified('verified', 'Verified'),
  insufficientEvidence('insufficient_evidence', 'Insufficient evidence'),
  rejected('rejected', 'Rejected');

  const ExternalReviewStatus(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static ExternalReviewStatus tryParse(String? value) {
    for (final status in ExternalReviewStatus.values) {
      if (status.storageValue == value) return status;
    }
    return ExternalReviewStatus.pending;
  }
}

const int kMaxExternalTransactions = 10;
const int kExternalEvidencePerTransaction = 2;

class ExternalEvidenceDraft {
  const ExternalEvidenceDraft({required this.kind, required this.bytes});

  final ExternalEvidenceKind kind;
  final Uint8List bytes;
}

class ExternalTransactionDraft {
  const ExternalTransactionDraft({
    required this.localId,
    required this.platform,
    required this.approximateDate,
    required this.itemName,
    required this.evidence,
    this.amount,
    this.listingUrl,
  });

  final String localId;
  final ExternalPlatform platform;
  final DateTime approximateDate;
  final String itemName;
  final double? amount;
  final String? listingUrl;
  final List<ExternalEvidenceDraft> evidence;

  ExternalTransactionDraft copyWith({
    ExternalPlatform? platform,
    DateTime? approximateDate,
    String? itemName,
    double? amount,
    String? listingUrl,
    List<ExternalEvidenceDraft>? evidence,
    bool clearAmount = false,
    bool clearListingUrl = false,
  }) {
    return ExternalTransactionDraft(
      localId: localId,
      platform: platform ?? this.platform,
      approximateDate: approximateDate ?? this.approximateDate,
      itemName: itemName ?? this.itemName,
      amount: clearAmount ? null : amount ?? this.amount,
      listingUrl: clearListingUrl ? null : listingUrl ?? this.listingUrl,
      evidence: evidence ?? this.evidence,
    );
  }
}

/// Returns a message when this transaction cannot be submitted.
String? validateExternalTransaction(
  ExternalTransactionDraft draft, {
  DateTime? today,
}) {
  final item = draft.itemName.trim();
  if (item.length < 2) {
    return 'Enter the item that was sold.';
  }
  if (item.length > 80) {
    return 'Keep the item name under 80 characters.';
  }

  final day = DateTime(
    draft.approximateDate.year,
    draft.approximateDate.month,
    draft.approximateDate.day,
  );
  final now = today ?? DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  if (day.isAfter(end)) {
    return 'The transaction date cannot be in the future.';
  }
  if (day.isBefore(DateTime(2010))) {
    return 'Choose a date from 2010 onward.';
  }

  if (draft.amount != null &&
      (draft.amount! <= 0 || draft.amount! > 10000000)) {
    return 'Enter an amount greater than 0, or leave it blank.';
  }

  final url = draft.listingUrl?.trim() ?? '';
  if (url.isNotEmpty &&
      !(url.startsWith('https://') || url.startsWith('http://'))) {
    return 'The listing link should start with https://.';
  }
  if (url.length > 500) {
    return 'The listing link is too long.';
  }

  if (draft.evidence.length != kExternalEvidencePerTransaction) {
    return 'Add two pieces of evidence for this transaction.';
  }
  if (draft.evidence[0].kind == draft.evidence[1].kind) {
    return 'Use two different kinds of evidence, such as a conversation and payment proof.';
  }
  if (draft.evidence.any((item) => item.bytes.isEmpty)) {
    return 'Each piece of evidence needs a photo.';
  }
  return null;
}

/// An empty list is a valid skip. A claimed range never sets the score.
String? validateExternalHistory({
  required List<ExternalTransactionDraft> transactions,
  required ClaimedSellingRange? claimedRange,
  DateTime? today,
}) {
  if (transactions.isEmpty) return null;
  if (transactions.length > kMaxExternalTransactions) {
    return 'You can add up to $kMaxExternalTransactions previous transactions.';
  }
  if (claimedRange == null) {
    return 'Choose your approximate previous selling experience.';
  }
  for (var i = 0; i < transactions.length; i++) {
    final error = validateExternalTransaction(transactions[i], today: today);
    if (error != null) {
      return 'Transaction ${i + 1}: $error';
    }
  }
  return null;
}
