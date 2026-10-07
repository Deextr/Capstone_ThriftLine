import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
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
    final meetsMin = count >= kReportEvidenceMinCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photo Evidence', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text(
          required
              ? 'Add at least one photo that helps us review your report.'
              : 'Add photos that help us review your report (optional).',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (evidenceError != null) ...[
          const SizedBox(height: 6),
          Text(
            evidenceError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < count; i++)
              _EvidenceThumb(
                bytes: evidence[i].bytes,
                onRemove: () => onRemove(i),
                onPreview: () => _showPreview(context, evidence[i].bytes),
              ),
            if (!atMax)
              _AddEvidenceButton(
                onGallery: onAddGallery,
                onCamera: onAddCamera,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$count of $kReportEvidenceMaxCount photos added',
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: meetsMin ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        if (atMax)
          Text(
            'You can upload up to $kReportEvidenceMaxCount photos.',
            style: AppTypography.caption,
          ),
      ],
    );
  }

  void _showPreview(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({
    required this.bytes,
    required this.onRemove,
    required this.onPreview,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPreview,
              child: Image.memory(
                bytes,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
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

  Future<void> _pick(BuildContext context, Future<String?> Function() pick) async {
    final err = await pick();
    if (err != null && context.mounted) {
      showThriftSnackBar(context, err, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context, onGallery),
      onLongPress: onCamera == null
          ? null
          : () => _pick(context, onCamera!),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              'Add Photo',
              style: AppTypography.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
