/// Validates auction bid text before calling [place_bid].
String? bidAmountValidationError({
  required String rawInput,
  required double minimumBid,
}) {
  final cleanText = rawInput.replaceAll(RegExp(r'[^\d.]'), '');
  if (cleanText.trim().isEmpty) {
    return 'Enter a bid amount.';
  }
  final amount = double.tryParse(cleanText);
  if (amount == null || !amount.isFinite) {
    return 'Enter a valid number for your bid.';
  }
  if (amount <= 0) {
    return 'Bid must be greater than zero.';
  }
  if (amount < minimumBid) {
    return 'Bid must be at least ${minimumBid.toStringAsFixed(0)}.';
  }
  return null;
}

double? parseValidatedBidAmount(String rawInput) {
  final cleanText = rawInput.replaceAll(RegExp(r'[^\d.]'), '');
  final amount = double.tryParse(cleanText);
  if (amount == null || !amount.isFinite) return null;
  return amount;
}
