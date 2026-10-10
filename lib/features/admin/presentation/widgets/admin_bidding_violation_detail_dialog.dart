import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/admin_bidding_violations_service.dart';
import '../../domain/auction_bidding_violations.dart';
import 'admin_marketplace_user_dialogs.dart';

Future<void> showBiddingViolationDetailDialog({
  required BuildContext context,
  required BiddingViolatorSummary buyer,
  required Future<List<BiddingViolationHistoryEntry>> Function() loadHistory,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _BiddingViolationDetailDialog(
        buyer: buyer,
        loadHistory: loadHistory,
      );
    },
  );
}

class _BiddingViolationDetailDialog extends StatefulWidget {
  const _BiddingViolationDetailDialog({
    required this.buyer,
    required this.loadHistory,
  });

  final BiddingViolatorSummary buyer;
  final Future<List<BiddingViolationHistoryEntry>> Function() loadHistory;

  @override
  State<_BiddingViolationDetailDialog> createState() =>
      _BiddingViolationDetailDialogState();
}

class _BiddingViolationDetailDialogState
    extends State<_BiddingViolationDetailDialog> {
  List<BiddingViolationHistoryEntry> _history = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.loadHistory();
      if (!mounted) return;
      setState(() {
        _history = rows;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load violation history.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final buyer = widget.buyer;
    final width = MediaQuery.sizeOf(context).width;
    final thresholdReached =
        buyer.violationCount >= kAuctionBiddingViolationBanThreshold;
    final now = DateTime.now();
    final enforcement = buyer.enforcementStatusAt(now);
    final canBid = enforcement == BiddingEnforcementStatus.active;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Bidding violation details',
              style: AppTypography.subheading,
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: width < 640 ? width : 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Buyer information', style: AppTypography.tableBodyMedium),
              SizedBox(height: 8),
              Text(buyer.displayName, style: AppTypography.tableBody),
              if (buyer.username.isNotEmpty)
                Text(
                  '@${buyer.username}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              if (buyer.email.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(buyer.email, style: AppTypography.caption),
              ],
              const SizedBox(height: 4),
              Text(
                'User ID: ${buyer.userId}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MarketplaceStatusBadge(status: buyer.accountStatus),
                  _EnforcementBadge(status: enforcement),
                ],
              ),
              SizedBox(height: 6),
              Text(
                '${buyer.violationCount} qualifying '
                '${buyer.violationCount == 1 ? 'violation' : 'violations'} · '
                '${buyer.violationStage}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Divider(height: 28),
              Text('Enforcement status', style: AppTypography.tableBodyMedium),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Bidding eligibility',
                value: canBid ? 'Allowed to bid' : 'Cannot place bids',
              ),
              if (buyer.restrictedUntil != null &&
                  enforcement == BiddingEnforcementStatus.restricted) ...[
                _InfoRow(
                  label: 'Time remaining',
                  value: formatBiddingRestrictionRemaining(
                    buyer.restrictedUntil!,
                    now: now,
                  ),
                ),
                _InfoRow(
                  label: 'Restriction ends',
                  value: formatAdminTableDateTime(buyer.restrictedUntil!),
                ),
              ],
              if (buyer.permanentlyDisabledAt != null) ...[
                _InfoRow(
                  label: 'Disabled at',
                  value: formatAdminTableDateTime(buyer.permanentlyDisabledAt!),
                ),
              ],
              if (buyer.disableReason != null &&
                  buyer.disableReason!.trim().isNotEmpty)
                _InfoRow(label: 'Reason', value: buyer.disableReason!),
              _InfoRow(
                label: 'Penalty threshold',
                value: thresholdReached
                    ? 'Reached (3 violations)'
                    : 'Not reached',
              ),
              const Divider(height: 28),
              Text('Violation history', style: AppTypography.tableBodyMedium),
              SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(_error!, style: AppTypography.body)
              else if (_history.isEmpty)
                Text(
                  'No violation records found.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                )
              else
                for (final entry in _history) ...[
                  _HistoryCard(entry: entry),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EnforcementBadge extends StatelessWidget {
  const _EnforcementBadge({required this.status});

  final BiddingEnforcementStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = switch (status) {
      BiddingEnforcementStatus.active => (
        AppColors.primaryDark,
        AppColors.primaryLight,
      ),
      BiddingEnforcementStatus.restricted => (
        AppColors.warningForeground,
        AppColors.warningSoft,
      ),
      BiddingEnforcementStatus.banned => (
        AppColors.errorForeground,
        AppColors.errorSoft,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Text(
        'Bidding: ${biddingEnforcementStatusLabel(status)}',
        style: AppTypography.badge.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTypography.caption)),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final BiddingViolationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatOrdinalViolationCount(entry.violationNumber),
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: 4),
          Text(entry.violationType, style: AppTypography.tableBody),
          Text(
            entry.productName,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatAdminTableDateTime(entry.createdAt),
            style: AppTypography.caption.copyWith(
              color: AppColors.textHint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Payment due: ${formatAdminTableDateTime(entry.paymentDueAt)}',
            style: AppTypography.caption.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Penalty: ${consequenceDisplayLabel(entry.consequence)}',
            style: AppTypography.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
