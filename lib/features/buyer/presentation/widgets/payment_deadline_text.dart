import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';

/// Displays the stored payment deadline. The clock only refreshes the label.
class PaymentDeadlineText extends StatefulWidget {
  const PaymentDeadlineText({super.key, required this.due, this.style});

  final DateTime due;
  final TextStyle? style;

  @override
  State<PaymentDeadlineText> createState() => _PaymentDeadlineTextState();
}

class _PaymentDeadlineTextState extends State<PaymentDeadlineText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatPaymentDeadline(widget.due),
      style: widget.style ?? AppTypography.caption,
    );
  }
}
