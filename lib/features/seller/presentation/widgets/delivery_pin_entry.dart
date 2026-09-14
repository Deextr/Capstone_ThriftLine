import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';

class DeliveryPinEntry extends StatefulWidget {
  const DeliveryPinEntry({
    super.key,
    required this.onSubmit,
    this.isLoading = false,
  });

  final Future<void> Function(String pin) onSubmit;
  final bool isLoading;

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
        Text('Verify delivery', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text(
          'Enter the Delivery PIN provided by the buyer.',
          style: AppTypography.caption,
        ),
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
          label: widget.isLoading ? 'Verifying…' : 'Verify Delivery',
          onPressed: widget.isLoading
              ? null
              : () => widget.onSubmit(_pin.text.trim()),
        ),
      ],
    );
  }
}
