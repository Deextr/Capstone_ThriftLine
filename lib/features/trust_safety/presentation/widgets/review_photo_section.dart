import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/review_rules.dart';
import '../../../../models/review_model.dart';
import '../../controllers/report_user_controller.dart';

class ReviewPhotoSection extends StatelessWidget {
  const ReviewPhotoSection({
    super.key,
    required this.existingPhotos,
    required this.newDrafts,
    required this.readOnly,
    required this.onAddGallery,
    this.onAddCamera,
    required this.onRemoveExisting,
    required this.onRemoveDraft,
  });

  final List<ReviewPhoto> existingPhotos;
  final List<ReportEvidenceDraft> newDrafts;
  final bool readOnly;
  final Future<String?> Function() onAddGallery;
  final Future<String?> Function()? onAddCamera;
  final void Function(ReviewPhoto photo) onRemoveExisting;
  final void Function(int index) onRemoveDraft;

  int get _totalCount => existingPhotos.length + newDrafts.length;

  @override
  Widget build(BuildContext context) {
    final atMax = _totalCount >= kReviewPhotoMaxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Product photos (optional)',
                style: AppTypography.subheading,
              ),
            ),
            Text(
              'Photos: $_totalCount/$kReviewPhotoMaxCount',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          atMax
              ? 'Maximum of $kReviewPhotoMaxCount photos reached.'
              : 'Show the item you received. JPG, PNG, or WebP · 5 MB each.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _totalCount + (readOnly || atMax ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < existingPhotos.length) {
                final photo = existingPhotos[index];
                return _NetworkThumb(
                  url: photo.publicUrl,
                  readOnly: readOnly,
                  onRemove: readOnly ? null : () => onRemoveExisting(photo),
                );
              }
              final draftIndex = index - existingPhotos.length;
              if (draftIndex < newDrafts.length) {
                return _MemoryThumb(
                  bytes: newDrafts[draftIndex].bytes,
                  onRemove: readOnly ? null : () => onRemoveDraft(draftIndex),
                );
              }
              return _AddPhotoButton(
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

class _NetworkThumb extends StatelessWidget {
  const _NetworkThumb({
    required this.url,
    required this.readOnly,
    this.onRemove,
  });

  final String? url;
  final bool readOnly;
  final VoidCallback? onRemove;

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
            child: url == null || url!.isEmpty
                ? Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_outlined),
                  )
                : Image.network(url!, width: 80, height: 80, fit: BoxFit.cover),
          ),
          if (onRemove != null)
            Positioned(
              top: -4,
              right: -4,
              child: _RemoveBadge(onTap: onRemove!),
            ),
        ],
      ),
    );
  }
}

class _MemoryThumb extends StatelessWidget {
  const _MemoryThumb({required this.bytes, this.onRemove});

  final Uint8List bytes;
  final VoidCallback? onRemove;

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
          if (onRemove != null)
            Positioned(
              top: -4,
              right: -4,
              child: _RemoveBadge(onTap: onRemove!),
            ),
        ],
      ),
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.textPrimary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.onGallery, this.onCamera});

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
            ),
          ],
        ),
      ),
    );
  }
}
