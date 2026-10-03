import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';
import '../features/buyer/domain/looking_for_lifecycle.dart';
import '../models/looking_for_model.dart';
import 'thrift_widgets.dart';

enum LookingForCardLayout { compact, feed, detail }

class LookingForCard extends StatelessWidget {
  const LookingForCard({
    super.key,
    required this.post,
    this.compact = true,
    this.layout,
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
  final LookingForCardLayout? layout;
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

  LookingForCardLayout get _layout {
    if (layout != null) return layout!;
    if (!compact) return LookingForCardLayout.detail;
    return LookingForCardLayout.compact;
  }

  @override
  Widget build(BuildContext context) {
    return switch (_layout) {
      LookingForCardLayout.feed => _feed(context),
      LookingForCardLayout.detail => _detail(context),
      LookingForCardLayout.compact => _compact(context),
    };
  }

  Widget _feed(BuildContext context) {
    final hasImage =
        post.thumbnailUrl != null && post.thumbnailUrl!.trim().isNotEmpty;
    final budgetLine =
        '${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThriftAvatar(imageUrl: post.buyerAvatar, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.buyerName.trim().isEmpty
                                ? 'Buyer'
                                : post.buyerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatRelativeTime(post.createdAt),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                          if (post.location.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              post.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _menu(),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: AppTypography.subheading.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (post.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        post.description,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      budgetLine,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    if (post.size != null && post.size!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Size ${post.size!.trim()}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (hasImage) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: onTap,
                child: _FeedImage(url: post.thumbnailUrl!),
              ),
            ],
            const SizedBox(height: 4),
            const Divider(height: 1, color: AppColors.border),
            _feedActions(context),
          ],
        ),
      ),
    );
  }

  Widget _feedActions(BuildContext context) {
    if (!showShare && !showRespondButton) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showShare)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 22),
                label: const Text('Share'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          if (showRespondButton)
            ThriftButton(
              label: 'I Have This Item',
              expand: true,
              onPressed: onRespond,
            ),
        ],
      ),
    );
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
                  label: 'I Have This Item',
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

class _FeedImage extends StatelessWidget {
  const _FeedImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (_, _) => const ColoredBox(
          color: AppColors.surfaceVariant,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        errorWidget: (_, _, _) => const ColoredBox(
          color: AppColors.surfaceVariant,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: AppColors.textHint,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
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
