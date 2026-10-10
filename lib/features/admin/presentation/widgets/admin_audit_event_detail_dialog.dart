import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/admin_audit_log_models.dart';
import 'admin_ui_components.dart';

Future<void> showAdminAuditEventDetailDialog({
  required BuildContext context,
  required AdminAuditLogRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: _AdminAuditEventDetailBody(row: row),
      ),
    ),
  );
}

class _AdminAuditEventDetailBody extends StatefulWidget {
  const _AdminAuditEventDetailBody({required this.row});

  final AdminAuditLogRow row;

  @override
  State<_AdminAuditEventDetailBody> createState() =>
      _AdminAuditEventDetailBodyState();
}

class _AdminAuditEventDetailBodyState
    extends State<_AdminAuditEventDetailBody> {
  bool _showRawMetadata = false;

  AdminAuditLogRow get row => widget.row;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat(
      'MMM d, yyyy • h:mm:ss a',
    ).format(row.createdAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Audit event details',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Event overview',
                  children: [
                    _Line(label: 'Action', value: row.displayEvent),
                    _Line(label: 'Date & time', value: when),
                    _Line(label: 'Result', value: row.resultLabel),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AdminStatusBadge(status: row.status),
                    ),
                  ],
                ),
                _Section(
                  title: 'Performed by',
                  children: [
                    _Line(label: 'Role', value: row.actorRoleDisplayLine),
                    _Line(label: 'Name', value: row.actorNameDisplayLine),
                    if (!row.isSystemAction &&
                        row.actorEmail != null &&
                        row.actorEmail!.trim().isNotEmpty &&
                        row.actorNameDisplayLine != row.actorEmail!.trim())
                      _Line(label: 'Email', value: row.actorEmail!),
                  ],
                ),
                _Section(
                  title: 'Affected record',
                  children: [
                    _Line(label: 'Module', value: row.moduleLabel),
                    _Line(label: 'Target', value: row.targetDisplayPrimary),
                    if (row.targetDisplaySecondary != null)
                      _Line(
                        label: 'Reference',
                        value: row.targetDisplaySecondary!,
                      ),
                    if (row.targetType != null)
                      _Line(
                        label: 'Target type',
                        value: AdminAuditLogRow.titleCase(row.targetType!),
                      ),
                    if (row.targetId != null)
                      _Line(label: 'Reference', value: row.targetId!),
                  ],
                ),
                _Section(
                  title: 'Reason and context',
                  children: [
                    Text(
                      row.summary.trim().isEmpty ? '—' : row.summary,
                      style: AppTypography.body.copyWith(height: 1.45),
                    ),
                    ..._safeDetailLines(row.details),
                  ],
                ),
                _Section(
                  title: 'Changes made',
                  children: _changeLines(row.details),
                ),
                if (row.details.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showRawMetadata = !_showRawMetadata),
                    icon: Icon(
                      _showRawMetadata
                          ? Icons.expand_less
                          : Icons.code_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _showRawMetadata
                          ? 'Hide raw metadata'
                          : 'View raw metadata',
                    ),
                  ),
                  if (_showRawMetadata)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SelectableText(
                        _redactedMetadata(row.details),
                        style: AppTypography.caption.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
                if (row.eventType != row.displayEvent)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Technical event: ${row.eventType}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _safeDetailLines(Map<String, dynamic> details) {
    const skip = {
      'password',
      'token',
      'otp',
      'secret',
      'previous_status',
      'new_status',
      'reason',
      'notes',
    };
    final widgets = <Widget>[];
    for (final entry in details.entries) {
      final key = entry.key.toLowerCase();
      if (skip.any(key.contains)) continue;
      if (_sensitiveDetailKey(entry.key)) continue;
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      widgets.add(
        _Line(label: AdminAuditLogRow.titleCase(entry.key), value: value),
      );
    }
    return widgets;
  }

  List<Widget> _changeLines(Map<String, dynamic> details) {
    final previous = details['previous_status']?.toString();
    final next = details['new_status']?.toString();
    if (previous == null && next == null) {
      return [
        Text(
          'No structured before/after values were recorded for this event.',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ];
    }
    return [
      if (previous != null) _Line(label: 'Previous value', value: previous),
      if (next != null) _Line(label: 'Updated value', value: next),
    ];
  }

  bool _sensitiveDetailKey(String key) {
    final k = key.toLowerCase();
    return k.contains('password') ||
        k.contains('token') ||
        k.contains('otp') ||
        k.contains('secret');
  }

  String _redactedMetadata(Map<String, dynamic> details) {
    final buffer = StringBuffer();
    for (final entry in details.entries) {
      if (_sensitiveDetailKey(entry.key)) {
        buffer.writeln('${entry.key}: [redacted]');
      } else {
        buffer.writeln('${entry.key}: ${entry.value}');
      }
    }
    return buffer.toString().trim();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}
