import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../domain/id_image_quality.dart';

class IdSideReviewCard extends StatelessWidget {
  const IdSideReviewCard({
    super.key,
    required this.title,
    required this.bytes,
    required this.quality,
    required this.checking,
    required this.onCapture,
  });

  final String title;
  final Uint8List? bytes;
  final IdQualityResult? quality;
  final bool checking;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final passed = quality?.passed == true;
    final warning = quality?.severity == IdQualitySeverity.warning;
    final failed = quality != null && !quality!.passed && !warning;
    final border = passed
        ? AppColors.success
        : warning
            ? AppColors.warning
            : failed
                ? AppColors.error
                : AppColors.primary.withValues(alpha: 0.45);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.subheading),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1.6,
              child: bytes == null
                  ? ColoredBox(
                      color: AppColors.primaryLight.withValues(alpha: 0.4),
                      child: const Center(
                        child: Icon(
                          Icons.credit_card_outlined,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    )
                  : Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
          const SizedBox(height: 12),
          if (checking)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Checking ID and photo quality…', style: AppTypography.caption),
              ],
            )
          else if (quality == null)
            Text(
              'Required. Open the camera to capture this side.',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  passed
                      ? Icons.check_circle
                      : warning
                          ? Icons.warning_amber_rounded
                          : Icons.cancel,
                  size: 18,
                  color: passed
                      ? AppColors.success
                      : warning
                          ? AppColors.warning
                          : AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    quality!.message,
                    style: AppTypography.body.copyWith(
                      color: passed
                          ? AppColors.success
                          : warning
                              ? AppColors.warning
                              : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: checking ? null : onCapture,
              icon: Icon(bytes == null ? Icons.photo_camera_outlined : Icons.refresh),
              label: Text(bytes == null ? 'Capture $title' : 'Retake $title'),
            ),
          ),
        ],
      ),
    );
  }
}
