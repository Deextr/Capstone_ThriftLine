import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/seller_application_rejection_reasons.dart';

/// Returns the applicant-facing rejection text, or null if the admin cancelled.
Future<String?> showSellerApplicationRejectDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => const _SellerApplicationRejectDialog(),
  );
}

class _SellerApplicationRejectDialog extends StatefulWidget {
  const _SellerApplicationRejectDialog();

  @override
  State<_SellerApplicationRejectDialog> createState() =>
      _SellerApplicationRejectDialogState();
}

class _SellerApplicationRejectDialogState
    extends State<_SellerApplicationRejectDialog> {
  String? _reasonId;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  String? get _resolvedReason => sellerRejectionReasonMessage(
    reasonId: _reasonId,
    otherDetail: _otherCtrl.text,
  );

  bool get _canReject => _resolvedReason != null;

  @override
  Widget build(BuildContext context) {
    final otherSelected = _reasonId == kSellerApplicationRejectOtherId;

    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height - media.viewInsets.bottom - 220).clamp(
      140.0,
      420.0,
    );

    return AlertDialog(
      title: Text('Reject application'),
      content: SizedBox(
        width: media.size.width < 480 ? media.size.width : 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Choose why this application is being rejected. The applicant will see this reason.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _reasonId,
                onChanged: (value) {
                  setState(() => _reasonId = value);
                },
                child: Column(
                  children: [
                    for (final reason in kSellerApplicationRejectReasons)
                      RadioListTile<String>(
                        value: reason.id,
                        title: Text(reason.label),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              if (otherSelected) ...[
                const SizedBox(height: 8),
                ThriftTextField(
                  label: 'Please specify',
                  hint: 'Please specify',
                  controller: _otherCtrl,
                  maxLines: 3,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep pending'),
        ),
        TextButton(
          onPressed: _canReject
              ? () => Navigator.pop(context, _resolvedReason)
              : null,
          child: const Text('Reject application'),
        ),
      ],
    );
  }
}
