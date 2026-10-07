import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
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
  required List<(String label, String value)> rows,
  required String confirmLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows) ...[
              Text(
                row.$1,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(row.$2, style: AppTypography.body.copyWith(height: 1.4)),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: destructive
                ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                : null,
          ),
        ),
      ],
    ),
  );
}
