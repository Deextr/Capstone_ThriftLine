import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/my_reports_controller.dart';

class MyReportsPaginationBar extends StatelessWidget {
  const MyReportsPaginationBar({super.key, this.onPageChanged});

  final VoidCallback? onPageChanged;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyReportsController>();
    if (!controller.showPagination) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _PageIconButton(
              icon: Icons.chevron_left_rounded,
              enabled: controller.canGoToPreviousPage,
              tooltip: 'Previous page',
              onPressed: () {
                context.read<MyReportsController>().goToPreviousPage();
                onPageChanged?.call();
              },
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Page ${controller.currentPageNumber} of ${controller.totalPages}',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    controller.paginationRangeLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            _PageIconButton(
              icon: Icons.chevron_right_rounded,
              enabled: controller.canGoToNextPage,
              tooltip: 'Next page',
              onPressed: () {
                context.read<MyReportsController>().goToNextPage();
                onPageChanged?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PageIconButton extends StatelessWidget {
  const _PageIconButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      icon: Icon(icon, size: 28),
      color: enabled ? AppColors.primaryDark : AppColors.textHint,
      visualDensity: VisualDensity.compact,
    );
  }
}
