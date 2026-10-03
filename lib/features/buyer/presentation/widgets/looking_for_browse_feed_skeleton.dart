import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../widgets/skeleton_widgets.dart';

/// Skeleton for Browse Requests while the first feed load is in progress.
class LookingForBrowseFeedSkeleton extends StatelessWidget {
  const LookingForBrowseFeedSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: itemCount,
      itemBuilder: (_, index) => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: _FeedPostSkeleton(),
      ),
    );
  }
}

class _FeedPostSkeleton extends StatelessWidget {
  const _FeedPostSkeleton();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: ThriftShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  const SkeletonCircle(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 140, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 56, height: 12),
                      ],
                    ),
                  ),
                  const SkeletonBox(width: 24, height: 24, radius: 12),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: double.infinity, height: 18),
                  SizedBox(height: 8),
                  SkeletonBox(width: double.infinity, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 10),
                  SkeletonBox(width: 100, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const AspectRatio(
              aspectRatio: 4 / 3,
              child: SkeletonBox(width: double.infinity, height: 200),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: const [
                  SkeletonBox(width: 88, height: 36, radius: 8),
                  Spacer(),
                  SkeletonBox(width: 140, height: 40, radius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
