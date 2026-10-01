import 'dart:convert';

/// Display labels for the seller trust score stored in Postgres.
///
/// The score itself is not calculated here. [resolveTrustLabel] only maps a
/// stored total onto Table 17, and prefers the stored class when the server
/// sent one.
const List<String> kTrustLabels = [
  'Highly Trusted Seller',
  'Trusted Seller',
  'New Seller',
  'Under Review',
  'Banned',
];

String resolveTrustLabel({required int score, String? storedLevel}) {
  final stored = storedLevel?.trim();
  if (stored != null && stored.isNotEmpty && kTrustLabels.contains(stored)) {
    return stored;
  }
  if (score >= 90) return 'Highly Trusted Seller';
  if (score >= 75) return 'Trusted Seller';
  if (score >= 60) return 'New Seller';
  if (score >= 40) return 'Under Review';
  return 'Banned';
}

/// Criterion scores already computed by `recalculate_seller_trust`.
class SellerTrustBreakdown {
  const SellerTrustBreakdown({
    required this.identity,
    required this.transactions,
    required this.ratings,
    required this.reports,
    this.verifiedExternal,
    this.completedThriftline,
    this.eligibleTransactions,
  });

  final int identity;
  final int transactions;
  final int ratings;
  final int reports;
  final int? verifiedExternal;
  final int? completedThriftline;
  final int? eligibleTransactions;

  static SellerTrustBreakdown? tryParse(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    final identity = _score(raw['iv']);
    final transactions = _score(raw['st']);
    final ratings = _score(raw['ur']);
    final reports = _score(raw['cr']);
    if (identity == null ||
        transactions == null ||
        ratings == null ||
        reports == null) {
      return null;
    }
    return SellerTrustBreakdown(
      identity: identity,
      transactions: transactions,
      ratings: ratings,
      reports: reports,
      verifiedExternal: _score(raw['verified_external']),
      completedThriftline: _score(raw['completed_thriftline']),
      eligibleTransactions: _score(raw['eligible_transactions']),
    );
  }

  static int? _score(Object? value) {
    if (value is num) return value.toInt();
    return null;
  }
}
