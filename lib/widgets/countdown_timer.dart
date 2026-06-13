import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({super.key, required this.endTime, this.style});

  final DateTime endTime;
  final TextStyle? style;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.endTime.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = widget.endTime.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatCountdown(_remaining),
      style: widget.style ??
          AppTypography.caption.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
