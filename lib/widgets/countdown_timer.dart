import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.endTime,
    this.style,
    this.onExpired,
  });

  final DateTime endTime;
  final TextStyle? style;
  final VoidCallback? onExpired;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer>
    with WidgetsBindingObserver {
  Timer? _timer;
  late Duration _remaining;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(CountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endTime != widget.endTime) {
      _expiredNotified = false;
      _tick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  Duration _computeRemaining() {
    final remaining = widget.endTime.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  void _tick() {
    if (!mounted) return;
    final remaining = _computeRemaining();
    setState(() => _remaining = remaining);
    if (!_expiredNotified && remaining == Duration.zero) {
      _expiredNotified = true;
      widget.onExpired?.call();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatCountdown(_remaining),
      style:
          widget.style ??
          AppTypography.caption.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
