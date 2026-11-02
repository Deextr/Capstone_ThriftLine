import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';

class DeliveryPinEntry extends StatefulWidget {
  const DeliveryPinEntry({
    super.key,
    required this.onSubmit,
    this.isLoading = false,
    this.title = 'Verify delivery',
    this.hint = 'Enter the Delivery PIN provided by the buyer.',
    this.buttonLabel = 'Verify Delivery',
  });

  final Future<void> Function(String pin) onSubmit;
  final bool isLoading;
  final String title;
  final String hint;
  final String buttonLabel;

  @override
  State<DeliveryPinEntry> createState() => _DeliveryPinEntryState();
}

class _DeliveryPinEntryState extends State<DeliveryPinEntry> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text(widget.hint, style: AppTypography.caption),
        const SizedBox(height: 8),
        ThriftTextField(
          hint: '______',
          controller: _pin,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        const SizedBox(height: 12),
        ThriftButton(
          label: widget.isLoading ? 'Verifying…' : widget.buttonLabel,
          onPressed: widget.isLoading
              ? null
              : () => widget.onSubmit(_pin.text.trim()),
        ),
      ],
    );
  }
}
