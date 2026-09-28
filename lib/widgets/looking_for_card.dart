import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/formatters.dart';
import '../models/looking_for_model.dart';
import 'thrift_widgets.dart';

class LookingForCard extends StatelessWidget {
  const LookingForCard({
    super.key,
    required this.post,
    this.showRespondButton = false,
    this.showShare = false,
    this.showOwnerActions = false,
    this.onRespond,
    this.onShare,
    this.onEdit,
    this.onDelete,
    this.onTap,
  });

  final LookingForModel post;
  final bool showRespondButton;
  final bool showShare;
  final bool showOwnerActions;
  final VoidCallback? onRespond;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
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
                          Row(
                            children: [
                              Text(
                                formatRelativeTime(post.createdAt),
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textHint,
                                ),
                              ),
                              if (post.location.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Text(
                                  '•',
                                  style: TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    post.location,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textHint,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showOwnerActions)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz,
                          color: AppColors.textHint,
                        ),
                        onSelected: (value) {
                          if (value == 'edit') onEdit?.call();
                          if (value == 'delete') onDelete?.call();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: AppTypography.heading.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(post.description, style: AppTypography.body),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Budget: ',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${formatCurrency(post.budgetMin)} – ${formatCurrency(post.budgetMax)}',
                          style: AppTypography.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ThriftBadge(
                          label: post.category.label,
                          variant: BadgeVariant.primary,
                        ),
                        if (post.size != null && post.size!.isNotEmpty)
                          ThriftBadge(
                            label: 'Size: ${post.size}',
                            variant: BadgeVariant.neutral,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (post.thumbnailUrl != null) ...[
                CachedNetworkImage(
                  imageUrl: post.thumbnailUrl!,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    height: 250,
                    color: AppColors.background,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 250,
                    color: AppColors.background,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (showShare)
                      _buildActionButton(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: onShare ?? () {},
                      ),
                    const Spacer(),
                    if (showRespondButton)
                      ThriftButton(
                        label: 'I Have This!',
                        variant: ThriftButtonVariant.primary,
                        expand: false,
                        onPressed: onRespond,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.textSecondary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
