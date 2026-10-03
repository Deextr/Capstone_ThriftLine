import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/seller_trust.dart';
import '../../../../core/utils/seller_trust_explanation.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Seller-facing trust score breakdown for My Shop.
class MyShopTrustPanel extends StatefulWidget {
  const MyShopTrustPanel({super.key, required this.user});

  final AuthUser user;

  @override
  State<MyShopTrustPanel> createState() => _MyShopTrustPanelState();
}

class _MyShopTrustPanelState extends State<MyShopTrustPanel> {
  bool _showCalculation = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final breakdown = user.trustBreakdown;
    final label = resolveTrustLabel(
      score: user.trustScore,
      storedLevel: user.trustLevel,
    );
    final level = trustClassifications.firstWhere(
      (c) => c.label == label,
      orElse: () => trustClassifications.last,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trust Score',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScoreRing(
                score: user.trustScore,
                accent: AppColors.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.trustScore} / 100',
                      style: AppTypography.heading.copyWith(
                        fontSize: 26,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(level.icon, size: 16, color: level.color),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: level.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      level.description,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (breakdown != null) ...[
            const SizedBox(height: 16),
            Text(
              SellerTrustExplanation.scoreSummary(
                trustScore: user.trustScore,
                breakdown: breakdown,
                isVerified: user.isVerified,
                ratingAverage: user.rating,
                ratingCount: user.ratingCount,
              ),
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'How your score is built',
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your trust score reflects verification, completed transactions, '
              'ratings on completed orders, and admin-confirmed reports.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _FactorCard(
              icon: Icons.verified_user_outlined,
              title: 'Identity Verification',
              headline: SellerTrustExplanation.identityTitle(
                isVerified: user.isVerified,
                ivScore: breakdown.identity,
              ),
              detail: SellerTrustExplanation.identityDetail(
                isVerified: user.isVerified,
                ivScore: breakdown.identity,
              ),
              factorScore: breakdown.identity,
            ),
            _FactorCard(
              icon: Icons.local_shipping_outlined,
              title: 'Successful Transactions',
              headline: sellerTrustTransactionCount(breakdown) <= 0
                  ? 'No counted transactions yet'
                  : '${sellerTrustTransactionCount(breakdown)} completed '
                      'transaction${sellerTrustTransactionCount(breakdown) == 1 ? '' : 's'}',
              detail: SellerTrustExplanation.transactionDetail(breakdown),
              factorScore: breakdown.transactions,
            ),
            _FactorCard(
              icon: Icons.star_outline_rounded,
              title: 'Customer Rating',
              headline: SellerTrustExplanation.ratingTitle(
                average: user.rating,
                ratingCount: user.ratingCount,
              ),
              detail: SellerTrustExplanation.ratingDetail(
                average: user.rating,
                ratingCount: user.ratingCount,
                urScore: breakdown.ratings,
              ),
              factorScore: breakdown.ratings,
              trailing: user.ratingCount > 0 && user.rating != null
                  ? _StarRow(rating: user.rating!)
                  : null,
            ),
            _FactorCard(
              icon: Icons.flag_outlined,
              title: 'Confirmed Reports',
              headline: SellerTrustExplanation.reportsTitle(
                sellerTrustConfirmedReportCount(breakdown),
              ),
              detail: SellerTrustExplanation.reportsDetail(
                confirmedReports: sellerTrustConfirmedReportCount(breakdown),
                crScore: breakdown.reports,
              ),
              factorScore: breakdown.reports,
            ),
            ..._buildTips(breakdown, user),
            InkWell(
              onTap: () => setState(() => _showCalculation = !_showCalculation),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(
                      _showCalculation
                          ? 'Hide calculation details'
                          : 'View calculation details',
                      style: AppTypography.body.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _showCalculation
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_showCalculation) _CalculationDetails(user: user, breakdown: breakdown),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Your trust breakdown is loading or unavailable. Pull to refresh '
              'or check back after your next sale or verification update.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTips(SellerTrustBreakdown breakdown, AuthUser user) {
    final tips = SellerTrustExplanation.improvementTips(
      breakdown: breakdown,
      isVerified: user.isVerified,
      ratingCount: user.ratingCount,
    );
    if (tips.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      Text(
        'Ways to strengthen trust',
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      ...tips.map(
        (tip) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TipRow(tip: tip),
        ),
      ),
    ];
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.accent});

  final int score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = (score.clamp(0, 100)) / 100;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: AppColors.surfaceVariant,
            color: accent,
          ),
          Text(
            '$score',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorCard extends StatelessWidget {
  const _FactorCard({
    required this.icon,
    required this.title,
    required this.headline,
    required this.detail,
    required this.factorScore,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String detail;
  final int factorScore;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$factorScore/100',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (factorScore.clamp(0, 100)) / 100,
                minHeight: 5,
                backgroundColor: AppColors.surfaceVariant,
                color: AppColors.primary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              headline,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailing != null) ...[const SizedBox(height: 4), trailing!],
            const SizedBox(height: 4),
            Text(
              detail,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = rating >= i + 1 - 0.25;
        return Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 16,
          color: filled ? AppColors.primary : AppColors.textHint,
        );
      }),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.tip});

  final SellerTrustTip tip;

  IconData get _icon => switch (tip.icon) {
    SellerTrustTipIcon.verification => Icons.badge_outlined,
    SellerTrustTipIcon.transactions => Icons.receipt_long_outlined,
    SellerTrustTipIcon.rating => Icons.star_outline,
    SellerTrustTipIcon.reports => Icons.handshake_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tip.title,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tip.body,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalculationDetails extends StatelessWidget {
  const _CalculationDetails({required this.user, required this.breakdown});

  final AuthUser user;
  final SellerTrustBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final w = breakdown.weights;
    final wIv = w?['iv'] ?? sellerTrustWeightIdentity;
    final wSt = w?['st'] ?? sellerTrustWeightTransactions;
    final wUr = w?['ur'] ?? sellerTrustWeightRatings;
    final wCr = w?['cr'] ?? sellerTrustWeightReports;
    final mirrored = mirrorTrustWeightedSum(breakdown);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weighted sum (server rubric)',
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _CalcLine(
            label: 'Identity (${(wIv * 100).round()}%)',
            value: breakdown.identity,
            weight: wIv,
          ),
          _CalcLine(
            label: 'Transactions (${(wSt * 100).round()}%)',
            value: breakdown.transactions,
            weight: wSt,
          ),
          _CalcLine(
            label: 'Ratings (${(wUr * 100).round()}%)',
            value: breakdown.ratings,
            weight: wUr,
          ),
          _CalcLine(
            label: 'Reports (${(wCr * 100).round()}%)',
            value: breakdown.reports,
            weight: wCr,
          ),
          const Divider(height: 20),
          Text(
            'Stored total: ${user.trustScore}/100',
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          if (mirrored != user.trustScore)
            Text(
              'Note: Factor combination rounds to $mirrored; your saved score is authoritative.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

class _CalcLine extends StatelessWidget {
  const _CalcLine({
    required this.label,
    required this.value,
    required this.weight,
  });

  final String label;
  final int value;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final contribution = (value * weight).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label × $value → $contribution pts',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
