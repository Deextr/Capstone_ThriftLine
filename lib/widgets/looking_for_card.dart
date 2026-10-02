import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';
import '../features/buyer/domain/looking_for_lifecycle.dart';
import '../models/looking_for_model.dart';
import 'thrift_widgets.dart';

class LookingForCard extends StatelessWidget {
  const LookingForCard({
    super.key,
    required this.post,
    this.compact = true,
    this.showRespondButton = false,
    this.showShare = false,
    this.showOwnerActions = false,
    this.showReport = false,
    this.onRespond,
    this.onShare,
    this.onEdit,
    this.onDelete,
    this.onRepost,
    this.onReport,
    this.onTap,
  });

  final LookingForModel post;
  final bool compact;
  final bool showRespondButton;
  final bool showShare;
  final bool showOwnerActions;
  final bool showReport;
  final VoidCallback? onRespond;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRepost;
  final VoidCallback? onReport;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (compact) return _compact(context);
    return _detail(context);
  }

  Widget _compact(BuildContext context) {
    final image = post.thumbnailUrl;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(url: image, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (post.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _metaLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      post.lifecycleLabel,
                      style: AppTypography.caption.copyWith(
                        color: _statusColor(post.lifecycle),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _menu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThriftAvatar(imageUrl: post.buyerAvatar, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.buyerName,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLine(),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            _menu(),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          post.lifecycleLabel,
          style: AppTypography.caption.copyWith(
            color: _statusColor(post.lifecycle),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(post.title, style: AppTypography.heading.copyWith(fontSize: 20)),
        if (post.description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(post.description, style: AppTypography.body),
        ],
        const SizedBox(height: 12),
        Text(
          'Budget ${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        if (post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _Thumb(url: post.thumbnailUrl, size: 220, expand: true),
          ),
        ],
        if (showShare || showRespondButton) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (showShare)
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
              const Spacer(),
              if (showRespondButton)
                ThriftButton(
                  label: 'I Have This',
                  expand: false,
                  onPressed: onRespond,
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _metaLine() {
    final parts = <String>[
      shortPersonName(post.buyerName),
      formatRelativeTime(post.createdAt),
    ];
    if (post.size != null && post.size!.trim().isNotEmpty) {
      parts.add(post.size!.trim());
    }
    return parts.join(' · ');
  }

  Widget _menu() {
    final items = <PopupMenuEntry<String>>[
      if (showShare) const PopupMenuItem(value: 'share', child: Text('Share')),
      if (showReport)
        const PopupMenuItem(value: 'report', child: Text('Report request')),
      if (showOwnerActions && post.canEdit)
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
      if (showOwnerActions && post.canRepost)
        const PopupMenuItem(value: 'repost', child: Text('Repost')),
      if (showOwnerActions && post.canDelete)
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ];
    if (items.isEmpty) return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      tooltip: 'Request actions',
      icon: const Icon(Icons.more_horiz, color: AppColors.textHint),
      onSelected: (value) {
        switch (value) {
          case 'share':
            onShare?.call();
          case 'report':
            onReport?.call();
          case 'edit':
            onEdit?.call();
          case 'repost':
            onRepost?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => items,
    );
  }
}

Color _statusColor(LookingForLifecycle lifecycle) {
  return switch (lifecycle) {
    LookingForLifecycle.removed => AppColors.error,
    LookingForLifecycle.expired ||
    LookingForLifecycle.closed ||
    LookingForLifecycle.deleted => AppColors.textSecondary,
    LookingForLifecycle.active ||
    LookingForLifecycle.fulfilled => AppColors.primaryDark,
  };
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.size, this.expand = false});

  final String? url;
  final double size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final width = expand ? double.infinity : size;
    final child = url == null || url!.isEmpty
        ? ColoredBox(
            color: AppColors.surfaceVariant,
            child: Icon(
              Icons.image_outlined,
              color: AppColors.textHint,
              size: expand ? 32 : 22,
            ),
          )
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => ColoredBox(
              color: AppColors.surfaceVariant,
              child: const Icon(
                Icons.image_outlined,
                color: AppColors.textHint,
              ),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: width, height: size, child: child),
    );
  }
}
