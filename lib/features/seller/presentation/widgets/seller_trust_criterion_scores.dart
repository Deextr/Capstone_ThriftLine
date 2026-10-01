import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/seller_trust.dart';

/// Seller-only view of the four stored criterion scores.
class SellerTrustCriterionScores extends StatelessWidget {
  const SellerTrustCriterionScores({super.key, required this.breakdown});

  final SellerTrustBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How this score is built',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Each part is scored from 0 to 100 on the server. Unconfirmed reports are not included.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        _ScoreRow(label: 'Identity verification', score: breakdown.identity),
        _ScoreRow(label: 'Completed orders', score: breakdown.transactions),
        if (breakdown.eligibleTransactions != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Verified outside ThriftLine: ${breakdown.verifiedExternal ?? 0}. Completed on ThriftLine: ${breakdown.completedThriftline ?? 0}. Counted: ${breakdown.eligibleTransactions}. Outside evidence is capped at 10 and only counts after an admin verifies it.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        _ScoreRow(label: 'Ratings', score: breakdown.ratings),
        _ScoreRow(label: 'Confirmed reports', score: breakdown.reports),
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '$score',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
