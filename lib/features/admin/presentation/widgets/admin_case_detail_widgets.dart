import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import 'admin_ui_components.dart';

/// Web-friendly case review layout (no AppBar — sits inside [AdminWebShell]).
class AdminCaseDetailPage extends StatelessWidget {
  const AdminCaseDetailPage({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.child,
    this.maxWidth = 920,
  });

  final String backLabel;
  final VoidCallback onBack;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(backLabel),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminCaseDetailHeader extends StatelessWidget {
  const AdminCaseDetailHeader({
    super.key,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.submittedAt,
    this.typeLabel,
  });

  final String title;
  final String status;
  final String statusLabel;
  final DateTime submittedAt;
  final String? typeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (typeLabel != null && typeLabel!.trim().isNotEmpty)
              AdminCaseTypeChip(label: typeLabel!),
            AdminStatusBadge(status: status, label: statusLabel),
          ],
        ),
        const SizedBox(height: 12),
        Text(title, style: AppTypography.pageTitle.copyWith(fontSize: 22)),
        const SizedBox(height: 6),
        Text(
          'Submitted ${formatAdminTableDateTime(submittedAt)}',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class AdminCaseTypeChip extends StatelessWidget {
  const AdminCaseTypeChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Flat section — no per-field cards.
class AdminCaseDetailSection extends StatelessWidget {
  const AdminCaseDetailSection({
    super.key,
    required this.title,
    required this.children,
    this.first = false,
  });

  final String title;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 24 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!first) const Divider(height: 1, color: AppColors.border),
          if (!first) const SizedBox(height: 24),
          Text(
            title.toUpperCase(),
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class AdminCaseDetailField extends StatelessWidget {
  const AdminCaseDetailField({
    super.key,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.body.copyWith(fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCaseDetailBodyText extends StatelessWidget {
  const AdminCaseDetailBodyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.body.copyWith(fontSize: 14, height: 1.5),
    );
  }
}

class AdminCasePartiesRow extends StatelessWidget {
  const AdminCasePartiesRow({
    super.key,
    required this.leftTitle,
    required this.leftName,
    this.leftLines = const [],
    required this.rightTitle,
    required this.rightName,
    this.rightLines = const [],
  });

  final String leftTitle;
  final String leftName;
  final List<String> leftLines;
  final String rightTitle;
  final String rightName;
  final List<String> rightLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final left = _PartyColumn(
          title: leftTitle,
          name: leftName,
          lines: leftLines,
        );
        final right = _PartyColumn(
          title: rightTitle,
          name: rightName,
          lines: rightLines,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 20), right],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 24),
              Container(width: 1, color: AppColors.border),
              const SizedBox(width: 24),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }
}

class _PartyColumn extends StatelessWidget {
  const _PartyColumn({
    required this.title,
    required this.name,
    required this.lines,
  });

  final String title;
  final String name;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(name, style: AppTypography.subheading.copyWith(fontSize: 15)),
        for (final line in lines)
          if (line.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              line.trim(),
              style: AppTypography.body.copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
      ],
    );
  }
}

class AdminCaseTimelineEvent {
  const AdminCaseTimelineEvent({
    required this.title,
    this.at,
    this.isComplete = true,
    this.isCurrent = false,
    this.subtitle,
    this.emphasisWarning = false,
  });

  final String title;
  final DateTime? at;
  final bool isComplete;
  final bool isCurrent;
  final String? subtitle;
  final bool emphasisWarning;
}

class AdminCaseTimeline extends StatelessWidget {
  const AdminCaseTimeline({super.key, required this.events});

  final List<AdminCaseTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text(
        'No activity recorded.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          _TimelineRow(event: events[i], showConnector: i < events.length - 1),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.showConnector});

  final AdminCaseTimelineEvent event;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final dotColor = event.emphasisWarning
        ? AppColors.warning
        : event.isCurrent
        ? AppColors.primary
        : event.isComplete
        ? AppColors.primary.withValues(alpha: 0.55)
        : AppColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: event.isCurrent
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                ),
                if (showConnector)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 16 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: AppTypography.body.copyWith(
                      fontWeight: event.isCurrent || event.emphasisWarning
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                      color: event.emphasisWarning ? AppColors.warning : null,
                    ),
                  ),
                  if (event.subtitle != null &&
                      event.subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.subtitle!.trim(),
                      style: AppTypography.caption.copyWith(
                        color: event.emphasisWarning
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (event.at != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatAdminTableDateTime(event.at!),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCaseDecisionPanel extends StatelessWidget {
  const AdminCaseDecisionPanel({
    super.key,
    required this.title,
    required this.children,
    this.lead,
  });

  final String title;
  final String? lead;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AdminCaseDetailSection(
      title: title,
      children: [
        if (lead != null && lead!.trim().isNotEmpty) ...[
          Text(
            lead!,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
