import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/report_user_controller.dart';
import '../../data/report_reasons.dart';

class ReportEvidenceSection extends StatelessWidget {
  const ReportEvidenceSection({
    super.key,
    required this.evidence,
    required this.evidenceError,
    required this.onAddGallery,
    this.onAddCamera,
    required this.onRemove,
    this.required = true,
  });

  final List<ReportEvidenceDraft> evidence;
  final String? evidenceError;
  final Future<String?> Function() onAddGallery;
  final Future<String?> Function()? onAddCamera;
  final void Function(int index) onRemove;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final count = evidence.length;
    final atMax = count >= kReportEvidenceMaxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                required ? 'Photo evidence' : 'Photo evidence (optional)',
                style: AppTypography.subheading,
              ),
            ),
            Text(
              'Evidence: $count/$kReportEvidenceMaxCount photos',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: count >= kReportEvidenceMinCount
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          atMax
              ? 'Maximum of $kReportEvidenceMaxCount photos reached.'
              : 'JPG, PNG, or WebP · 5 MB each · ${required ? 'At least 1 required' : 'Optional'}',
          style: AppTypography.caption,
        ),
        if (evidenceError != null) ...[
          const SizedBox(height: 6),
          Text(
            evidenceError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count + (atMax ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < count) {
                return _EvidenceThumb(
                  bytes: evidence[index].bytes,
                  onRemove: () => onRemove(index),
                );
              }
              return _AddEvidenceButton(
                onGallery: onAddGallery,
                onCamera: onAddCamera,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              color: AppColors.textPrimary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEvidenceButton extends StatelessWidget {
  const _AddEvidenceButton({required this.onGallery, this.onCamera});

  final Future<String?> Function() onGallery;
  final Future<String?> Function()? onCamera;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final err = await onGallery();
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
        }
      },
      onLongPress: onCamera == null
          ? null
          : () async {
              final err = await onCamera!();
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(err)));
              }
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            Text(
              onCamera != null ? 'Tap / hold' : 'Add photo',
              style: AppTypography.caption.copyWith(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
