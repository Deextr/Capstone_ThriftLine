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

/// WSM weights stored by `recalculate_seller_trust` (Table 2.3.2).
abstract final class SellerTrustWeights {
  static const double identity = sellerTrustWeightIdentity;
  static const double transactions = sellerTrustWeightTransactions;
  static const double ratings = sellerTrustWeightRatings;
  static const double reports = sellerTrustWeightReports;
}

const double sellerTrustWeightIdentity = 0.40;
const double sellerTrustWeightTransactions = 0.30;
const double sellerTrustWeightRatings = 0.20;
const double sellerTrustWeightReports = 0.10;

/// Mirrors PostgreSQL `trust_weighted_sum` for optional transparency UI only.
/// Criterion inputs must come from [SellerTrustBreakdown] (server-written).
int mirrorTrustWeightedSum(SellerTrustBreakdown breakdown) {
  return ((breakdown.identity * SellerTrustWeights.identity) +
          (breakdown.transactions * SellerTrustWeights.transactions) +
          (breakdown.ratings * SellerTrustWeights.ratings) +
          (breakdown.reports * SellerTrustWeights.reports))
      .round();
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
    this.confirmedReports,
    this.ratingCount,
    this.weights,
  });

  final int identity;
  final int transactions;
  final int ratings;
  final int reports;
  final int? verifiedExternal;
  final int? completedThriftline;
  final int? eligibleTransactions;
  final int? confirmedReports;
  final int? ratingCount;
  final Map<String, double>? weights;

  /// Count used for the ST rubric (ThriftLine + verified external, when present).
  int get transactionCountForRubric => sellerTrustTransactionCount(this);

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
    Map<String, double>? weights;
    final weightsRaw = raw['weights'];
    if (weightsRaw is Map) {
      weights = weightsRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is num ? value.toDouble() : 0,
        ),
      );
    }

    return SellerTrustBreakdown(
      identity: identity,
      transactions: transactions,
      ratings: ratings,
      reports: reports,
      verifiedExternal: _score(raw['verified_external']),
      completedThriftline: _score(raw['completed_thriftline']),
      eligibleTransactions:
          _score(raw['eligible_transactions']) ??
          _score(raw['completed_orders']),
      confirmedReports: _score(raw['confirmed_reports']),
      ratingCount: _score(raw['rating_count']),
      weights: weights,
    );
  }

  static int? _score(Object? value) {
    if (value is num) return value.toInt();
    return null;
  }
}

/// Transaction count backing the ST rubric (from server breakdown JSON).
int sellerTrustTransactionCount(SellerTrustBreakdown breakdown) =>
    breakdown.eligibleTransactions ??
    breakdown.completedThriftline ??
    0;

/// Admin-confirmed report count (from server breakdown JSON).
int sellerTrustConfirmedReportCount(SellerTrustBreakdown breakdown) =>
    breakdown.confirmedReports ?? 0;
