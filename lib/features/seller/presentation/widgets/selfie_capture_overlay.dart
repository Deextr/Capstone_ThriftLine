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
    this.subtitle,
  });

  final String message;
  final bool aligned;
  final bool capturing;
  final String? subtitle;

  Color get _frameColor {
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
                painter: _OvalCutoutPainter(hole: hole, color: _frameColor),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

class _OvalCutoutPainter extends CustomPainter {
  const _OvalCutoutPainter({required this.hole, required this.color});

  final Rect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      hole,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalCutoutPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color;
}
