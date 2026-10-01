import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_review_rules.dart';

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({super.key, required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return ThriftBadge(
      label: label ?? reportDecisionLabel(status),
      variant: adminStatusBadgeVariant(status),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 8),
          Text(
            'Please try again.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ThriftButton(label: 'Retry', onPressed: onRetry, expand: false),
        ],
      ),
    );
  }
}

class AdminQueueSkeleton extends StatelessWidget {
  const AdminQueueSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const ShimmerBox(width: 148, height: 14),
        const SizedBox(height: 20),
        for (var i = 0; i < rows; i++) ...[
          const ShimmerBox(width: double.infinity, height: 16),
          const SizedBox(height: 8),
          const ShimmerBox(width: 196, height: 12),
          const SizedBox(height: 8),
          const ShimmerBox(width: 88, height: 12),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class AdminDetailSkeleton extends StatelessWidget {
  const AdminDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: const [
        ShimmerBox(width: 96, height: 22, radius: 20),
        SizedBox(height: 12),
        ShimmerBox(width: double.infinity, height: 22),
        SizedBox(height: 8),
        ShimmerBox(width: 120, height: 12),
        SizedBox(height: 28),
        ShimmerBox(width: 80, height: 12),
        SizedBox(height: 8),
        ShimmerBox(width: double.infinity, height: 16),
        SizedBox(height: 6),
        ShimmerBox(width: 160, height: 12),
        SizedBox(height: 28),
        ShimmerBox(width: double.infinity, height: 14),
        SizedBox(height: 8),
        ShimmerBox(width: double.infinity, height: 14),
        SizedBox(height: 8),
        ShimmerBox(width: 220, height: 14),
      ],
    );
  }
}

class AdminQueueNavRow extends StatelessWidget {
  const AdminQueueNavRow({
    super.key,
    required this.label,
    required this.detail,
    required this.loading,
    required this.needsAttention,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final String detail;
  final bool loading;
  final bool needsAttention;
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.subheading),
                      const SizedBox(height: 2),
                      if (loading)
                        const ShimmerBox(width: 128, height: 12)
                      else
                        Text(
                          detail,
                          style: AppTypography.body.copyWith(
                            color: needsAttention
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                            fontWeight: needsAttention
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminQueueItem extends StatelessWidget {
  const AdminQueueItem({
    super.key,
    required this.title,
    required this.statusLabel,
    required this.status,
    required this.lines,
    required this.meta,
    required this.onTap,
    this.actionLabel = 'View',
  });

  final String title;
  final String statusLabel;
  final String status;
  final List<String> lines;
  final String meta;
  final VoidCallback onTap;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final visibleLines = lines.where((item) => item.trim().isNotEmpty);
    return Semantics(
      button: true,
      label: '$title, $statusLabel. $actionLabel',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.subheading),
              for (final line in visibleLines) ...[
                const SizedBox(height: 4),
                Text(
                  line,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(meta, style: AppTypography.caption),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminStatusChip(status: status, label: statusLabel),
                  Text(
                    actionLabel,
                    style: AppTypography.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminSectionLabel extends StatelessWidget {
  const AdminSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.label.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class AdminDetailBlock extends StatelessWidget {
  const AdminDetailBlock({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminSectionLabel(label),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class AdminKeyValueRow extends StatelessWidget {
  const AdminKeyValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: AppTypography.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.body.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminPersonBlock extends StatelessWidget {
  const AdminPersonBlock({
    super.key,
    required this.label,
    required this.name,
    required this.handle,
    this.role,
    this.shopName,
    this.embedded = false,
  });

  final String label;
  final String name;
  final String handle;
  final String? role;
  final String? shopName;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final trimmedHandle = handle.trim();
    final showHandle = trimmedHandle.isNotEmpty && trimmedHandle != name.trim();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 4),
        Text(name, style: AppTypography.subheading),
        if (showHandle) ...[
          const SizedBox(height: 2),
          Text(
            trimmedHandle,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (role != null && role!.trim().isNotEmpty && role!.trim() != label)
          Text(role!.trim(), style: AppTypography.caption),
        if (shopName != null && shopName!.trim().isNotEmpty)
          Text(shopName!.trim(), style: AppTypography.caption),
      ],
    );

    if (embedded) return content;
    return Padding(padding: const EdgeInsets.only(bottom: 28), child: content);
  }
}

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AdminQueueFilter value;
  final ValueChanged<AdminQueueFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final filter in AdminQueueFilter.values)
          AdminUnderlineFilter(
            label: adminQueueFilterLabel(filter),
            selected: filter == value,
            onTap: () => onChanged(filter),
          ),
      ],
    );
  }
}

class AdminUnderlineFilter extends StatelessWidget {
  const AdminUnderlineFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: selected ? AppGradients.primaryGradientLight : null,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  bottom: BorderSide(
                    color: selected ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminEvidenceGallery extends StatelessWidget {
  const AdminEvidenceGallery({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Text(
        'No evidence was attached.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < urls.length; i++)
          AdminPhotoThumb(
            label: urls.length == 1 ? 'Photo' : 'Photo ${i + 1}',
            url: urls[i],
            semanticLabel: 'Open evidence photo ${i + 1}',
          ),
      ],
    );
  }
}

class AdminPhotoThumb extends StatelessWidget {
  const AdminPhotoThumb({
    super.key,
    required this.label,
    required this.url,
    this.semanticLabel,
  });

  final String label;
  final String? url;
  final String? semanticLabel;

  static const double width = 104;
  static const double height = 132;

  @override
  Widget build(BuildContext context) {
    final resolved = url?.trim() ?? '';
    final canOpen = resolved.isNotEmpty;
    return Semantics(
      button: canOpen,
      label: semanticLabel ?? 'Open $label',
      child: GestureDetector(
        onTap: canOpen ? () => showAdminImagePreview(context, resolved) : null,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: canOpen
                    ? CachedNetworkImage(
                        imageUrl: resolved,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const _PhotoPlaceholder(),
                        errorWidget: (_, _, _) => const _PhotoPlaceholder(
                          icon: Icons.broken_image_outlined,
                        ),
                      )
                    : const _PhotoPlaceholder(),
              ),
              const SizedBox(height: 4),
              Text(label, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.icon = Icons.image_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AdminPhotoThumb.width,
      height: AdminPhotoThumb.height,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.textHint, size: 22),
    );
  }
}

Future<void> showAdminImagePreview(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: AppColors.textPrimary,
        child: Stack(
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => const SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
                errorWidget: (_, _, _) => const SizedBox(
                  height: 240,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Close',
                color: Colors.white,
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class AdminDecisionSection extends StatelessWidget {
  const AdminDecisionSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.subheading),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class AdminChoiceRow extends StatelessWidget {
  const AdminChoiceRow({
    super.key,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.subheading),
                      if (hint.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(hint, style: AppTypography.caption),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDecisionOption extends StatelessWidget {
  const AdminDecisionOption({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String value;
  final String? groupValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminChoiceRow(
      label: reportDecisionLabel(value),
      hint: reportDecisionHint(value),
      selected: value == groupValue,
      onTap: () => onChanged(value),
    );
  }
}

class AdminReportCard extends StatelessWidget {
  const AdminReportCard({
    super.key,
    required this.reporterName,
    required this.reporterRole,
    required this.reportedName,
    required this.reportedRole,
    required this.reason,
    required this.status,
    required this.statusLabel,
    required this.createdAt,
    required this.onView,
    this.reportId,
    this.kindLabel,
    this.preview,
    this.orderNumber,
  });

  final String reporterName;
  final String reporterRole;
  final String reportedName;
  final String reportedRole;
  final String reason;
  final String status;
  final String statusLabel;
  final DateTime createdAt;
  final String? reportId;
  final String? kindLabel;
  final String? preview;
  final String? orderNumber;
  final VoidCallback onView;

  Color get _accent => switch (status) {
    'under_review' => AppColors.warning,
    'resolved' || 'action_taken' => AppColors.success,
    'dismissed' => AppColors.textHint,
    _ => AppColors.border,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppConstants.radiusMd),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (reportId != null && reportId!.isNotEmpty)
                                  Text(
                                    '#${adminReportShortId(reportId!)}',
                                    style: AppTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                if (kindLabel != null && kindLabel!.isNotEmpty)
                                  Text(
                                    kindLabel!,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AdminStatusChip(status: status, label: statusLabel),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.subheading,
                      ),
                      if (preview != null && preview!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          preview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _ReportMetaLine(
                        label: 'Reporter',
                        value: '$reporterName · $reporterRole',
                      ),
                      _ReportMetaLine(
                        label: 'Reported',
                        value: '$reportedName · $reportedRole',
                      ),
                      if (orderNumber != null && orderNumber!.isNotEmpty)
                        _ReportMetaLine(label: 'Order', value: '#$orderNumber'),
                      _ReportMetaLine(
                        label: 'Date',
                        value: formatFullDate(createdAt),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'View report',
                        style: AppTypography.label.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportMetaLine extends StatelessWidget {
  const _ReportMetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: AppTypography.caption)),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
