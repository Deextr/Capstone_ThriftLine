import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../widgets/skeleton_widgets.dart';

class MyReportsListSkeleton extends StatelessWidget {
  const MyReportsListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ThriftShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => const _ReportCardSkeleton(),
      ),
    );
  }
}

class _ReportCardSkeleton extends StatelessWidget {
  const _ReportCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 72, height: 22, radius: 6),
              Spacer(),
              SkeletonBox(width: 88, height: 22, radius: 6),
            ],
          ),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 16),
          SizedBox(height: 8),
          SkeletonBox(width: 160, height: 12),
          SizedBox(height: 12),
          SkeletonBox(width: 120, height: 12),
        ],
      ),
    );
  }
}
