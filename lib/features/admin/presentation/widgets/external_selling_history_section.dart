import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../seller/domain/external_selling.dart';
import '../../data/external_history_service.dart';
import 'admin_review_widgets.dart';

class ExternalSellingHistorySection extends StatelessWidget {
  const ExternalSellingHistorySection({
    super.key,
    required this.claimedRange,
    required this.items,
    required this.busy,
    required this.onReview,
  });

  final String? claimedRange;
  final List<ExternalHistoryItem> items;
  final bool busy;
  final void Function(ExternalHistoryItem item, ExternalReviewStatus decision)
  onReview;

  @override
  Widget build(BuildContext context) {
    final verified = items
        .where((item) => item.status == ExternalReviewStatus.verified)
        .length;
    final insufficient = items
        .where(
          (item) => item.status == ExternalReviewStatus.insufficientEvidence,
        )
        .length;
    final rejected = items
        .where((item) => item.status == ExternalReviewStatus.rejected)
        .length;
    final claimed =
        ClaimedSellingRange.tryParse(claimedRange)?.label ?? 'Not provided';

    return AdminDetailBlock(
      label: 'External selling history',
      children: [
        AdminKeyValueRow(label: 'Claimed', value: claimed),
        AdminKeyValueRow(label: 'Submitted', value: '${items.length}'),
        AdminKeyValueRow(label: 'Verified', value: '$verified'),
        AdminKeyValueRow(label: 'Insufficient', value: '$insufficient'),
        AdminKeyValueRow(label: 'Rejected', value: '$rejected'),
        SizedBox(height: 8),
        Text(
          'Only verified transactions count, and at most 10. A claimed range does not set the score. These photos are outside ThriftLine.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (items.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'This applicant did not add previous transactions.',
            style: AppTypography.body,
          ),
        ],
        for (var i = 0; i < items.length; i++) ...[
          const SizedBox(height: 16),
          _HistoryCard(
            index: i + 1,
            item: items[i],
            busy: busy,
            onReview: onReview,
          ),
        ],
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.index,
    required this.item,
    required this.busy,
    required this.onReview,
  });

  final int index;
  final ExternalHistoryItem item;
  final bool busy;
  final void Function(ExternalHistoryItem item, ExternalReviewStatus decision)
  onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'External transaction $index',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          AdminKeyValueRow(label: 'Platform', value: item.platformLabel),
          AdminKeyValueRow(label: 'Item', value: item.itemName),
          AdminKeyValueRow(
            label: 'Amount',
            value: item.amount == null
                ? 'Not provided'
                : formatCurrency(item.amount!),
          ),
          AdminKeyValueRow(
            label: 'Date',
            value: formatFullDate(item.transactionDate),
          ),
          AdminKeyValueRow(
            label: 'Listing',
            value: (item.listingUrl ?? '').trim().isEmpty
                ? 'Not provided'
                : item.listingUrl!.trim(),
          ),
          AdminKeyValueRow(label: 'Status', value: item.status.label),
          if ((item.adminNote ?? '').trim().isNotEmpty)
            AdminKeyValueRow(label: 'Note', value: item.adminNote!.trim()),
          if (item.evidence.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final evidence in item.evidence)
                  AdminPhotoThumb(
                    label: evidence.kindLabel,
                    url: evidence.signedUrl,
                  ),
              ],
            ),
          ],
          if (item.status == ExternalReviewStatus.pending) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Action(
                  label: 'Verify',
                  busy: busy,
                  onPressed: () =>
                      onReview(item, ExternalReviewStatus.verified),
                ),
                _Action(
                  label: 'Insufficient evidence',
                  busy: busy,
                  onPressed: () =>
                      onReview(item, ExternalReviewStatus.insufficientEvidence),
                ),
                _Action(
                  label: 'Reject',
                  busy: busy,
                  onPressed: () =>
                      onReview(item, ExternalReviewStatus.rejected),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: Text(label),
    );
  }
}
