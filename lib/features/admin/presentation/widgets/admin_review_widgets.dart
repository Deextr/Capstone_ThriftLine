import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
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
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
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
          Text(message, textAlign: TextAlign.center, style: AppTypography.body),
          const SizedBox(height: 16),
          ThriftButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class AdminQueueNavRow extends StatelessWidget {
  const AdminQueueNavRow({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final int? count;
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppTypography.subheading)),
              if (count == null)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '$count',
                  style: AppTypography.subheading.copyWith(
                    color: count! > 0
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: AppTypography.subheading)),
                const SizedBox(width: 8),
                AdminStatusChip(status: status, label: statusLabel),
              ],
            ),
            for (final line in lines.where(
              (item) => item.trim().isNotEmpty,
            )) ...[
              const SizedBox(height: 4),
              Text(
                line,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(meta, style: AppTypography.caption),
            ],
            const SizedBox(height: 8),
            Text(
              actionLabel,
              style: AppTypography.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
      label.toUpperCase(),
      style: AppTypography.label.copyWith(
        letterSpacing: 0.6,
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
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionLabel(label),
          const SizedBox(height: 8),
          ...children,
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
  });

  final String label;
  final String name;
  final String handle;
  final String? role;
  final String? shopName;

  @override
  Widget build(BuildContext context) {
    return AdminDetailBlock(
      label: label,
      children: [
        Text(name, style: AppTypography.subheading),
        if (handle.isNotEmpty)
          Text(
            handle,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        if (role != null && role!.isNotEmpty)
          Text(role!, style: AppTypography.caption),
        if (shopName != null && shopName!.trim().isNotEmpty)
          Text(shopName!.trim(), style: AppTypography.caption),
      ],
    );
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
    return SegmentedButton<AdminQueueFilter>(
      segments: [
        for (final filter in AdminQueueFilter.values)
          ButtonSegment(
            value: filter,
            label: Text(adminQueueFilterLabel(filter)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (next) {
        if (next.isNotEmpty) onChanged(next.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.padded,
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
        'No evidence files were attached.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final url in urls)
          Semantics(
            button: true,
            label: 'Open evidence photo',
            child: GestureDetector(
              onTap: () => showAdminImagePreview(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: 88,
                    height: 88,
                    color: AppColors.surfaceVariant,
                  ),
                  errorWidget: (_, _, _) => Container(
                    width: 88,
                    height: 88,
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
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
    final selected = value == groupValue;
    return Semantics(
      button: true,
      selected: selected,
      label: reportDecisionLabel(value),
      child: InkWell(
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 22,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reportDecisionLabel(value),
                      style: AppTypography.subheading,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reportDecisionHint(value),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
