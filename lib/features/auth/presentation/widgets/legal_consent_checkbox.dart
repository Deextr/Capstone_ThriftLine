import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../domain/legal_documents.dart';

/// Explicit, opt-in consent to the Terms and Conditions and Privacy Policy.
///
/// Always renders unchecked unless the caller's [value] says otherwise — the
/// parent screens never seed it to `true`. The document names are tappable and
/// open the full text so consent can be informed.
class LegalConsentCheckbox extends StatefulWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Shown when the user tried to continue without agreeing.
  final String? errorText;
  final bool enabled;

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocumentType.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocumentType.privacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  void _openDocument(LegalDocumentType type) {
    context.push(RouteNames.legalDocument(type));
  }

  void _toggle() {
    if (!widget.enabled) return;
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && !widget.value;
    final linkStyle = AppTypography.body.copyWith(
      fontSize: 13,
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: widget.value
                ? AppColors.primaryLight.withValues(alpha: 0.35)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: hasError
                  ? AppColors.error
                  : widget.value
                  ? AppColors.primary
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: widget.value,
                onChanged: widget.enabled
                    ? (checked) => widget.onChanged(checked ?? false)
                    : null,
                activeColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text.rich(
                      TextSpan(
                        style: AppTypography.body.copyWith(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          const TextSpan(
                            text: 'I have read and agree to the ',
                          ),
                          TextSpan(
                            text: 'Terms and Conditions',
                            style: linkStyle,
                            recognizer: _termsRecognizer,
                          ),
                          const TextSpan(text: ' and the '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: linkStyle,
                            recognizer: _privacyRecognizer,
                          ),
                          const TextSpan(
                            text: '. You must agree before you can continue.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.value) ...[
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Consent recorded for version ${LegalDocuments.version}.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ] else if (hasError) ...[
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
