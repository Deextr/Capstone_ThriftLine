import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

/// Instructions-only step content for Become a Seller face verification.
/// Primary action lives in the parent screen footer (`Take a selfie`).
class FaceSelfieVerificationStep extends StatelessWidget {
  const FaceSelfieVerificationStep({
    super.key,
    required this.completed,
    required this.onRetake,
  });

  final bool completed;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    if (completed) {
      return _SuccessState(onRetake: onRetake);
    }
    return const _InstructionsState();
  }
}

class _InstructionsState extends StatelessWidget {
  const _InstructionsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'We’ll match your face to your ID using your front camera.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        _PreviewFrame(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.face_outlined,
                size: 72,
                color: AppColors.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 12),
              Text(
                'Face preview opens when you tap Take a selfie',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What to expect',
                style: AppTypography.subheading.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 12),
              const _InstructionRow(
                icon: Icons.photo_camera_outlined,
                text:
                    'Tap Take a selfie below to open the camera.',
              ),
              const _InstructionRow(
                icon: Icons.face_retouching_natural_outlined,
                text:
                    'Look at the camera, then turn right, turn left, and blink when prompted.',
              ),
              const _InstructionRow(
                icon: Icons.check_circle_outline,
                text:
                    'Your photo is taken automatically when your face is clear and still.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: AppColors.warning.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Before you start',
                    style: AppTypography.subheading.copyWith(fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const [
                  _AvoidItem(
                    icon: Icons.checkroom_outlined,
                    label: 'No hats',
                  ),
                  _AvoidItem(
                    icon: Icons.visibility_off_outlined,
                    label: 'No glasses',
                  ),
                  _AvoidItem(icon: Icons.masks_outlined, label: 'No masks'),
                ],
              ),
              const SizedBox(height: 12),
              const _InstructionRow(
                icon: Icons.light_mode_outlined,
                text: 'Stand in a well-lit area and keep your face uncovered.',
                dense: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({required this.onRetake});

  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: AppColors.success,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                'Face check passed',
                style: AppTypography.subheading.copyWith(
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your liveness steps and selfie were captured successfully.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onRetake,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retake face check'),
        ),
      ],
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.icon,
    required this.text,
    this.dense = false,
  });

  final IconData icon;
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: dense ? 18 : 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(
                fontSize: dense ? 14 : null,
                color: dense ? AppColors.textSecondary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvoidItem extends StatelessWidget {
  const _AvoidItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}
