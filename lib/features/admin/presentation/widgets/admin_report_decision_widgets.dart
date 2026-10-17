import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_report_decision_content.dart';
import '../../data/admin_review_rules.dart';
import 'admin_review_widgets.dart';

class AdminResponseTemplateDropdown extends StatelessWidget {
  const AdminResponseTemplateDropdown({
    super.key,
    required this.templates,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
  });

  final List<AdminResponseTemplate> templates;
  final String? selectedId;
  final ValueChanged<AdminResponseTemplate> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedId ?? templates.first.id,
      decoration: const InputDecoration(
        labelText: 'Response template',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (final t in templates)
          DropdownMenuItem(value: t.id, child: Text(t.label)),
      ],
      onChanged: enabled
          ? (id) {
              if (id == null) return;
              final t = templates.firstWhere((e) => e.id == id);
              onSelected(t);
            }
          : null,
    );
  }
}

class AdminEvidenceTypeChipSelector extends StatelessWidget {
  const AdminEvidenceTypeChipSelector({
    super.key,
    required this.selectedIds,
    required this.onToggle,
    this.enabled = true,
  });

  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in kAdminEvidenceTypeOptions)
          FilterChip(
            label: Text(option.label),
            selected: selectedIds.contains(option.id),
            onSelected: enabled ? (_) => onToggle(option.id) : null,
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            checkmarkColor: AppColors.primary,
          ),
      ],
    );
  }
}

class AdminEvidencePartySelector extends StatelessWidget {
  const AdminEvidencePartySelector({
    super.key,
    required this.target,
    required this.onChanged,
    required this.reporterLabel,
    required this.reportedLabel,
    this.enabled = true,
  });

  final AdminEvidenceRequestTarget target;
  final ValueChanged<AdminEvidenceRequestTarget> onChanged;
  final String reporterLabel;
  final String reportedLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reporter is the user who submitted the report. Reported user is the party being reported.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        AdminChoiceRow(
          label: 'Reporter',
          hint: reporterLabel,
          selected: target == AdminEvidenceRequestTarget.reporter,
          onTap: enabled
              ? () => onChanged(AdminEvidenceRequestTarget.reporter)
              : () {},
        ),
        AdminChoiceRow(
          label: 'Reported user',
          hint: reportedLabel,
          selected: target == AdminEvidenceRequestTarget.reportedUser,
          onTap: enabled
              ? () => onChanged(AdminEvidenceRequestTarget.reportedUser)
              : () {},
        ),
      ],
    );
  }
}

class AdminEditableGeneratedMessage extends StatelessWidget {
  const AdminEditableGeneratedMessage({
    super.key,
    required this.controller,
    required this.onChanged,
    this.error,
    this.label = 'Message to reporter',
    this.maxLength = kAdminResponseMaxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;
  final String label;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: label,
          hint: 'Edit the generated message if needed',
          controller: controller,
          maxLines: 4,
          error: error,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${controller.text.trim().length}/$maxLength',
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }
}

Future<bool?> showAdminDecisionConfirmDialog({
  required BuildContext context,
  required String title,
  List<(String label, String value)> rows = const [],
  required String confirmLabel,
  bool destructive = false,
  String? messagePreview,
  String? detailText,
}) {
  final width = MediaQuery.sizeOf(context).width;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 480 ? 16 : 28,
        vertical: 24,
      ),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (destructive)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 22,
                        color: AppColors.error,
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.gavel_outlined,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        title,
                        style: AppTypography.subheading.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (messagePreview != null &&
                          messagePreview.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Message to member',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant.withValues(
                              alpha: 0.65,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusSm,
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            messagePreview.trim(),
                            style: AppTypography.body.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                      for (var i = 0; i < rows.length; i++) ...[
                        SizedBox(
                          height: i == 0 &&
                                  (messagePreview == null ||
                                      messagePreview.trim().isEmpty)
                              ? 16
                              : 14,
                        ),
                        Text(
                          rows[i].$1,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rows[i].$2,
                          style: AppTypography.body.copyWith(height: 1.4),
                        ),
                      ],
                      if (detailText != null &&
                          detailText.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          detailText.trim(),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (destructive)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(confirmLabel),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(confirmLabel),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
