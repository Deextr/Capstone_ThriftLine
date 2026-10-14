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
    this.onClose,
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
  final VoidCallback? onClose;
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _LookingForCardShell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ThriftAvatar(imageUrl: post.buyerAvatar, size: 40),
                const SizedBox(width: 10),
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
                    ],
                  ),
                ),
                _menu(hideShareInMenu: showShare),
              ],
            ),
            const SizedBox(height: 12),
            _LookingForInfoChips(post: post, showLifecycle: true),
            const SizedBox(height: 10),
            Text(
              post.title,
              style: AppTypography.subheading.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (post.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                post.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (hasImage) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _FeedImage(url: post.thumbnailUrl!),
              ),
            ],
            if (showShare || showRespondButton) ...[
              const SizedBox(height: 14),
              _feedActions(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _feedActions(BuildContext context) {
    return Row(
      children: [
        if (showShare)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        if (showShare && showRespondButton) const SizedBox(width: 10),
        if (showRespondButton)
          Expanded(
            flex: showShare ? 1 : 2,
            child: ThriftButton(
              label: 'I Have This',
              expand: true,
              onPressed: onRespond,
            ),
          ),
      ],
    );
  }

  Widget _compact(BuildContext context) {
    final image = post.thumbnailUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _LookingForCardShell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(url: image, size: 76),
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
                  const SizedBox(height: 6),
                  _LookingForStatusChip(
                    label: post.lifecycleLabel,
                    lifecycle: post.lifecycle,
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
                  const SizedBox(height: 8),
                  Text(
                    '${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _metaLine(includeBudget: false),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            _menu(hideShareInMenu: false),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context) {
    return _LookingForCardShell(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThriftAvatar(imageUrl: post.buyerAvatar, size: 44),
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
                      formatRelativeTime(post.createdAt),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              _menu(hideShareInMenu: showShare),
            ],
          ),
          const SizedBox(height: 14),
          _LookingForInfoChips(post: post, showLifecycle: true),
          const SizedBox(height: 12),
          Text(
            post.title,
            style: AppTypography.heading.copyWith(fontSize: 20, height: 1.2),
          ),
          if (post.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.description,
              style: AppTypography.body.copyWith(height: 1.45),
            ),
          ],
          if (post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _Thumb(url: post.thumbnailUrl, size: 220, expand: true),
            ),
          ],
          if (showShare || showRespondButton) ...[
            const SizedBox(height: 16),
            _feedActions(context),
          ],
        ],
      ),
    );
  }

  String _metaLine({bool includeBudget = true}) {
    final parts = <String>[
      post.category.label,
      formatRelativeTime(post.createdAt),
    ];
    if (post.size != null && post.size!.trim().isNotEmpty) {
      parts.add('Size ${post.size!.trim()}');
    }
    if (includeBudget) {
      parts.add(
        '${formatCurrency(post.budgetMin)}–${formatCurrency(post.budgetMax)}',
      );
    }
    return parts.join(' · ');
  }

  Widget _menu({required bool hideShareInMenu}) {
    final items = <PopupMenuEntry<String>>[
      if (showShare && !hideShareInMenu)
        const PopupMenuItem(value: 'share', child: Text('Share')),
      if (showReport)
        const PopupMenuItem(value: 'report', child: Text('Report request')),
      if (showOwnerActions && post.canClose)
        const PopupMenuItem(
          value: 'close',
          child: Text('Mark as fulfilled'),
        ),
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
      icon: Icon(Icons.more_horiz, color: AppColors.textHint),
      onSelected: (value) {
        switch (value) {
          case 'share':
            onShare?.call();
          case 'report':
            onReport?.call();
          case 'close':
            onClose?.call();
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

class _LookingForCardShell extends StatelessWidget {
  const _LookingForCardShell({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

class _LookingForStatusChip extends StatelessWidget {
  const _LookingForStatusChip({
    required this.label,
    required this.lifecycle,
  });

  final String label;
  final LookingForLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(lifecycle);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _LookingForInfoChips extends StatelessWidget {
  const _LookingForInfoChips({
    required this.post,
    required this.showLifecycle,
  });

  final LookingForModel post;
  final bool showLifecycle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _pill(
          post.category.label,
          foreground: AppColors.textSecondary,
          background: AppColors.surfaceVariant,
        ),
        _pill(
          '${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}',
          foreground: AppColors.primaryDark,
          background: AppColors.primaryLight.withValues(alpha: 0.35),
        ),
        if (post.size != null && post.size!.trim().isNotEmpty)
          _pill(
            'Size ${post.size!.trim()}',
            foreground: AppColors.textSecondary,
            background: AppColors.surfaceVariant,
          ),
        if (showLifecycle)
          _LookingForStatusChip(
            label: post.lifecycleLabel,
            lifecycle: post.lifecycle,
          ),
      ],
    );
  }

  Widget _pill(
    String text, {
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
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
        placeholder: (_, _) => ColoredBox(
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
        errorWidget: (_, _, _) => ColoredBox(
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
              child: Icon(
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
