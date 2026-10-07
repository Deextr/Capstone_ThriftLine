import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/report_seller_search.dart';

class ReportSellerSuggestionTile extends StatelessWidget {
  const ReportSellerSuggestionTile({
    super.key,
    required this.candidate,
    required this.onTap,
  });

  final ReportSellerCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            ThriftAvatar(
              imageUrl: candidate.avatarUrl,
              name: candidate.primaryLabel,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.primaryLabel,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (candidate.secondaryLabel != null)
                    Text(
                      candidate.secondaryLabel!,
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportSellerSelectedCard extends StatelessWidget {
  const ReportSellerSelectedCard({
    super.key,
    required this.candidate,
    required this.onChange,
  });

  final ReportSellerCandidate candidate;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ThriftAvatar(
            imageUrl: candidate.avatarUrl,
            name: candidate.primaryLabel,
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seller being reported',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  candidate.primaryLabel,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (candidate.secondaryLabel != null)
                  Text(
                    candidate.secondaryLabel!,
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}
