import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

/// Oval face guide with a single status pill, matching the ID capture overlay.
class SelfieCaptureOverlay extends StatelessWidget {
  const SelfieCaptureOverlay({
    super.key,
    required this.message,
    this.aligned = false,
    this.capturing = false,
    this.preCaptureGlow = 0,
    this.subtitle,
  });

  final String message;
  final bool aligned;
  final bool capturing;

  /// 0–1 progress of the pre-capture frame brightening animation.
  final double preCaptureGlow;
  final String? subtitle;

  Color get _frameColor {
    if (preCaptureGlow > 0) {
      return Color.lerp(
        AppColors.success,
        Colors.white,
        Curves.easeOut.transform(preCaptureGlow.clamp(0.0, 1.0)),
      )!;
    }
    if (capturing || aligned) return AppColors.success;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final holeW = size.width * 0.84;
          final holeH = holeW * 1.28;
          final hole = Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.46),
            width: holeW.clamp(120, size.width * 0.94),
            height: holeH.clamp(160, size.height * 0.72),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _OvalCutoutPainter(
                  hole: hole,
                  color: _frameColor,
                  preCaptureGlow: preCaptureGlow,
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: hole.bottom + 16,
                child: _StatusPill(
                  color: _frameColor,
                  message: capturing ? 'Capturing…' : message,
                  subtitle: subtitle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.color,
    required this.message,
    this.subtitle,
  });

  final Color color;
  final String message;
  final String? subtitle;

  IconData get _leadingIcon {
    if (message.startsWith('Checking')) return Icons.hourglass_top_outlined;
    if (message.startsWith('Hold still')) return Icons.flash_on_outlined;
    if (message.startsWith('Capturing')) return Icons.photo_camera_outlined;
    if (color == AppColors.success) return Icons.check_circle_outline;
    return Icons.face_retouching_natural_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_leadingIcon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OvalCutoutPainter extends CustomPainter {
  const _OvalCutoutPainter({
    required this.hole,
    required this.color,
    this.preCaptureGlow = 0,
  });

  final Rect hole;
  final Color color;
  final double preCaptureGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = preCaptureGlow.clamp(0.0, 1.0);
    final dimAlpha = 0.55 - (glow * 0.22);
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: dimAlpha),
    );

    if (glow > 0) {
      for (var ring = 3; ring >= 1; ring--) {
        final spread = glow * ring * 5;
        canvas.drawOval(
          hole.inflate(spread),
          Paint()
            ..color = AppColors.primary.withValues(alpha: 0.12 * glow / ring)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + glow,
        );
      }
      canvas.drawOval(
        hole,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.08 * glow)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawOval(
      hole,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 + (glow * 5),
    );
  }

  @override
  bool shouldRepaint(covariant _OvalCutoutPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.color != color ||
      oldDelegate.preCaptureGlow != preCaptureGlow;
}
