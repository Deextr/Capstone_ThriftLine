import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/buyer_transaction_history_controller.dart';
import '../../data/buyer_transaction.dart';

/// Refund progress inside the transaction details sheet.
class BuyerRefundStatusSection extends StatelessWidget {
  const BuyerRefundStatusSection({super.key, required this.transaction});

  final BuyerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final state = transaction.refundState;
    if (state == null) return const SizedBox.shrink();
    final complete = buyerRefundStateIsComplete(state);
    final needsAction =
        state == BuyerRefundState.awaitingBuyerClaim ||
        transaction.needsGcashDetails;
    final accent = complete
        ? AppColors.success
        : needsAction
        ? AppColors.warning
        : AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            buyerRefundHeadline(
              state,
              gcashSent: transaction.refundGcashSubmitted,
            ),
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            buyerRefundExplanation(
              state,
              gcashSent: transaction.refundGcashSubmitted,
            ),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (state == BuyerRefundState.awaitingBuyerClaim &&
              transaction.refundClaimLink != null) ...[
            const SizedBox(height: 12),
            _ClaimLinkAction(transaction: transaction),
          ],
          if (transaction.needsGcashDetails) ...[
            const SizedBox(height: 14),
            _RefundGcashForm(transaction: transaction),
          ],
          if (state == BuyerRefundState.manualCompleted &&
              transaction.manualRefundReference != null) ...[
            const SizedBox(height: 10),
            Text(
              'GCash reference: ${transaction.manualRefundReference}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (complete && transaction.refundCompletedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Completed ${formatFullDate(transaction.refundCompletedAt!)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClaimLinkAction extends StatelessWidget {
  const _ClaimLinkAction({required this.transaction});

  final BuyerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final link = transaction.refundClaimLink;
    final expires = transaction.refundClaimLinkExpiresAt;
    if (link == null) {
      return Text(
        'PayMongo has not shared a claim link yet. Pull down to refresh later.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }
    if (transaction.claimLinkExpired) {
      return Text(
        'This claim link has expired. We will follow up once PayMongo '
        'confirms what happened to the refund.',
        style: AppTypography.caption.copyWith(color: AppColors.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftButton(
          label: 'Open PayMongo claim link',
          icon: Icons.open_in_new_rounded,
          onPressed: () async {
            final opened = await context
                .read<BuyerTransactionHistoryController>()
                .openRefundClaimLink(transaction);
            if (!opened && context.mounted) {
              showThriftSnackBar(
                context,
                'We could not open the claim link. Try again.',
                isError: true,
              );
            }
          },
        ),
        if (expires != null) ...[
          const SizedBox(height: 6),
          Text(
            'Claim before ${formatFullDate(expires)}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _RefundGcashForm extends StatefulWidget {
  const _RefundGcashForm({required this.transaction});

  final BuyerTransaction transaction;

  @override
  State<_RefundGcashForm> createState() => _RefundGcashFormState();
}

class _RefundGcashFormState extends State<_RefundGcashForm> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  String? _nameError;
  String? _mobileError;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _nameError = validateGcashAccountName(_nameController.text);
      _mobileError = validateGcashMobileNumber(_mobileController.text);
    });
    if (_nameError != null || _mobileError != null) return;
    final ok = await context
        .read<BuyerTransactionHistoryController>()
        .submitRefundGcash(
          transaction: widget.transaction,
          accountName: _nameController.text,
          mobileNumber: _mobileController.text,
        );
    if (ok && mounted) {
      showThriftSnackBar(context, 'GCash details sent. We will update you.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerTransactionHistoryController>();
    final busy = controller.isSubmittingGcash;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Name on GCash account',
          controller: _nameController,
          error: _nameError,
          readOnly: busy,
          maxLength: 80,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 10),
        ThriftTextField(
          label: 'GCash mobile number',
          hint: '09171234567',
          controller: _mobileController,
          error: _mobileError,
          readOnly: busy,
          keyboardType: TextInputType.phone,
          onChanged: (_) {
            if (_mobileError != null) setState(() => _mobileError = null);
          },
        ),
        if (controller.gcashError != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.gcashError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 12),
        ThriftButton(
          label: busy ? 'Sending…' : 'Send GCash details',
          isLoading: busy,
          onPressed: busy ? null : _submit,
        ),
        const SizedBox(height: 6),
        Text(
          'Only ThriftLine admins can see these details. They are used for '
          'this refund only.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
