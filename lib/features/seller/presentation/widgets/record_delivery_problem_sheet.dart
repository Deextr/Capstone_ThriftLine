import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_reasons.dart';

/// Bottom sheet for sellers to record a failed delivery while out for delivery.
class RecordDeliveryProblemSheet extends StatefulWidget {
  const RecordDeliveryProblemSheet({super.key});

  static Future<({DeliveryFailureReason reason, String? details})?> show(
    BuildContext context,
  ) {
    return showModalBottomSheet<
      ({DeliveryFailureReason reason, String? details})?
    >(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const RecordDeliveryProblemSheet(),
    );
  }

  @override
  State<RecordDeliveryProblemSheet> createState() =>
      _RecordDeliveryProblemSheetState();
}

class _RecordDeliveryProblemSheetState
    extends State<RecordDeliveryProblemSheet> {
  DeliveryFailureReason? _reason;
  final _details = TextEditingController();
  String? _detailsError;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _selectReason(DeliveryFailureReason reason) {
    setState(() {
      _reason = reason;
      if (reason != DeliveryFailureReason.other) {
        _details.clear();
        _detailsError = null;
      }
    });
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) {
      showThriftSnackBar(context, 'Choose a reason.', isError: true);
      return;
    }
    String? trimmedDetails;
    if (reason == DeliveryFailureReason.other) {
      final error = deliveryFailureOtherDetailsError(_details.text);
      if (error != null) {
        setState(() => _detailsError = error);
        return;
      }
      trimmedDetails = _details.text.trim();
    }
    Navigator.pop(context, (reason: reason, details: trimmedDetails));
  }

  @override
  Widget build(BuildContext context) {
    final showOtherField = _reason == DeliveryFailureReason.other;

    return KeyboardSafeSheet(
      action: ThriftButton(label: 'Submit', onPressed: _submit),
      children: [
        Text('Record delivery problem', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text(
          'Choose what prevented this delivery from being completed.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppConstants.spacingMd),
        for (final reason in DeliveryFailureReason.values) ...[
          RadioListTile<DeliveryFailureReason>(
            value: reason,
            groupValue: _reason,
            onChanged: (value) {
              if (value != null) _selectReason(value);
            },
            title: Text(reason.label, style: AppTypography.body),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
        if (showOtherField) ...[
          const SizedBox(height: 8),
          ThriftTextField(
            label: 'Please describe the delivery problem',
            hint:
                'The rider reported that the delivery address could not be located.',
            controller: _details,
            maxLines: 4,
            maxLength: kReportDetailsMaxLength,
            error: _detailsError,
            onChanged: (_) {
              setState(() {
                if (_detailsError != null) _detailsError = null;
              });
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_details.text.length}/$kReportDetailsMaxLength',
              style: AppTypography.caption,
            ),
          ),
        ],
      ],
    );
  }
}
