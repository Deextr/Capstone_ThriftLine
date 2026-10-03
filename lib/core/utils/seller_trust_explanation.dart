import 'seller_trust.dart';

/// Human-readable copy for the seller My Shop trust panel.
///
/// Uses server-written criterion scores and counts from [SellerTrustBreakdown].
/// Does not compute alternate trust totals for display as the authoritative score.
abstract final class SellerTrustExplanation {
  static String transactionRangeLabel(int count) {
    if (count <= 0) return '0 completed transactions';
    if (count <= 10) return '1–10 transaction range';
    if (count <= 20) return '11–20 transaction range';
    if (count <= 30) return '21–30 transaction range';
    if (count <= 50) return '31–50 transaction range';
    return 'above 50 transactions';
  }

  static String transactionDetail(SellerTrustBreakdown breakdown) {
    final count = sellerTrustTransactionCount(breakdown);
    final range = transactionRangeLabel(count);
    final thrift = breakdown.completedThriftline;
    final external = breakdown.verifiedExternal;
    if (thrift != null && external != null && (external > 0 || thrift != count)) {
      return 'You have $count transactions counted toward trust '
          '($thrift completed on ThriftLine'
          '${external > 0 ? ', $external verified outside ThriftLine (capped at 10)' : ''}). '
          'This places you in the $range.';
    }
    if (count <= 0) {
      return 'You do not have completed transactions counted toward trust yet. '
          'Successful completed orders can strengthen this part of your score.';
    }
    return 'You currently have $count completed transaction${count == 1 ? '' : 's'}. '
        'This places you in the $range.';
  }

  static String identityTitle({required bool isVerified, required int ivScore}) {
    if (ivScore >= 100) return 'Fully verified';
    if (isVerified || ivScore >= 75) return 'Verified';
    if (ivScore > 0) return 'Partially verified';
    return 'Not verified';
  }

  static String identityDetail({
    required bool isVerified,
    required int ivScore,
  }) {
    if (ivScore >= 100) {
      return 'Your identity checks are complete, which strengthens your trust score.';
    }
    if (isVerified || ivScore >= 75) {
      return 'Your identity has been reviewed and verified, which helps buyers trust your shop.';
    }
    if (ivScore > 0) {
      return 'Some verification steps are complete. Finishing identity verification can strengthen your trust profile.';
    }
    return 'Complete identity verification so buyers know your account has been reviewed.';
  }

  static String ratingTitle({
    required double? average,
    required int ratingCount,
  }) {
    if (ratingCount <= 0 || average == null) return 'No ratings yet';
    return '${average.toStringAsFixed(1)} / 5';
  }

  static String ratingDetail({
    required double? average,
    required int ratingCount,
    required int urScore,
  }) {
    if (ratingCount <= 0 || average == null) {
      return 'You do not have buyer ratings on completed orders yet. '
          'When you do, positive ratings can strengthen this part of your score. '
          'Until then, ThriftLine uses a neutral rating factor ($urScore/100).';
    }
    return 'Your average rating from $ratingCount review${ratingCount == 1 ? '' : 's'} '
        'is ${average.toStringAsFixed(1)} out of 5. '
        'Strong ratings on completed transactions help strengthen your trust score.';
  }

  static String reportsTitle(int confirmedReports) {
    if (confirmedReports <= 0) return 'No confirmed reports';
    if (confirmedReports == 1) return '1 confirmed report';
    return '$confirmedReports confirmed reports';
  }

  static String reportsDetail({
    required int confirmedReports,
    required int crScore,
  }) {
    if (confirmedReports <= 0) {
      return 'You have no admin-confirmed reports. Reports still under review are not counted here.';
    }
    return 'You have $confirmedReports admin-confirmed report${confirmedReports == 1 ? '' : 's'}. '
        'Confirmed reports can lower this factor (currently $crScore/100). '
        'Reports that are still under review are not treated as confirmed violations.';
  }

  /// Short narrative from stored factors — not a substitute for [trustScore].
  static String scoreSummary({
    required int trustScore,
    required SellerTrustBreakdown breakdown,
    required bool isVerified,
    required double? ratingAverage,
    required int ratingCount,
  }) {
    final parts = <String>[];

    if (breakdown.identity >= 75 || isVerified) {
      parts.add('Verified identity is helping your score');
    } else if (breakdown.identity > 0) {
      parts.add('Completing verification would help your score');
    } else {
      parts.add('Identity verification is an area to improve');
    }

    final txCount = sellerTrustTransactionCount(breakdown);
    if (breakdown.transactions >= 60) {
      parts.add('your transaction history is a strong contributor');
    } else if (txCount > 0) {
      parts.add('you have some successful transactions, and more completed orders can help');
    } else {
      parts.add('completing successful orders can strengthen your profile');
    }

    if (ratingCount > 0 && (ratingAverage ?? 0) >= 4) {
      parts.add('buyer ratings are working in your favor');
    } else if (ratingCount == 0) {
      parts.add('ratings will matter more as buyers review completed orders');
    } else {
      parts.add('consistent service on completed orders can improve ratings over time');
    }

    final confirmed = sellerTrustConfirmedReportCount(breakdown);
    if (confirmed > 0) {
      parts.add('confirmed reports may be holding your score back');
    } else {
      parts.add('you have no confirmed reports affecting trust');
    }

    return 'Your trust score is $trustScore/100. '
        '${parts[0].substring(0, 1).toUpperCase()}${parts[0].substring(1)}. '
        '${parts[1].substring(0, 1).toUpperCase()}${parts[1].substring(1)}. '
        '${parts[2].substring(0, 1).toUpperCase()}${parts[2].substring(1)}. '
        '${parts[3].substring(0, 1).toUpperCase()}${parts[3].substring(1)}.';
  }

  static List<SellerTrustTip> improvementTips({
    required SellerTrustBreakdown breakdown,
    required bool isVerified,
    required int ratingCount,
  }) {
    final tips = <SellerTrustTip>[];
    if (breakdown.identity < 100 && !isVerified) {
      tips.add(
        const SellerTrustTip(
          title: 'Complete identity verification',
          body:
              'Verification helps buyers know that your account has been reviewed.',
          icon: SellerTrustTipIcon.verification,
        ),
      );
    } else if (breakdown.identity < 100) {
      tips.add(
        const SellerTrustTip(
          title: 'Finish remaining verification steps',
          body:
              'Each verified identity check strengthens the identity portion of your score.',
          icon: SellerTrustTipIcon.verification,
        ),
      );
    }

    if (breakdown.transactions < 80) {
      tips.add(
        const SellerTrustTip(
          title: 'Complete more successful orders',
          body:
              'Successful completed transactions can strengthen your trust profile over time.',
          icon: SellerTrustTipIcon.transactions,
        ),
      );
    }

    if (ratingCount == 0) {
      tips.add(
        const SellerTrustTip(
          title: 'Earn ratings from buyers',
          body:
              'After completed orders, buyer reviews contribute to your rating factor.',
          icon: SellerTrustTipIcon.rating,
        ),
      );
    }

    if (sellerTrustConfirmedReportCount(breakdown) > 0) {
      tips.add(
        const SellerTrustTip(
          title: 'Maintain good transaction practices',
          body:
              'Confirmed reports can affect your trust score. Clear communication and accurate listings help.',
          icon: SellerTrustTipIcon.reports,
        ),
      );
    }

    return tips;
  }
}

enum SellerTrustTipIcon { verification, transactions, rating, reports }

class SellerTrustTip {
  const SellerTrustTip({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final SellerTrustTipIcon icon;
}
