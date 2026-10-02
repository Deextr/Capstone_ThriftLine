import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

class PhoneOtpCodeInput extends StatefulWidget {
  const PhoneOtpCodeInput({
    super.key,
    required this.controller,
    this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  State<PhoneOtpCodeInput> createState() => _PhoneOtpCodeInputState();
}

class _PhoneOtpCodeInputState extends State<PhoneOtpCodeInput> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focusNode.removeListener(_rebuild);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    return GestureDetector(
      onTap: widget.enabled ? () => _focusNode.requestFocus() : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: List.generate(6, (index) {
              final filled = index < digits.length;
              final focused =
                  widget.enabled &&
                  _focusNode.hasFocus &&
                  index == digits.length.clamp(0, 5);
              final border = widget.hasError
                  ? AppColors.error
                  : focused
                  ? AppColors.primary
                  : AppColors.border;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: border,
                      width: focused || widget.hasError ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    filled ? digits[index] : '',
                    style: AppTypography.heading.copyWith(
                      fontSize: 22,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              );
            }),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  if (value.length == 6) widget.onCompleted?.call(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
