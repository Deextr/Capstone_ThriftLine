import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../domain/id_image_quality.dart';

/// Darkened camera overlay with an ID-1 card window and placement hint.
class IdCaptureOverlay extends StatelessWidget {
  const IdCaptureOverlay({super.key, this.aligned = false});

  /// Green when a document-like card fills the guide; red otherwise.
  final bool aligned;

  static const double cardAspect = IdCaptureGuide.cardAspect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hole = _holeRect(constraints.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _CutoutPainter(hole: hole, aligned: aligned),
              ),
              Positioned.fromRect(
                rect: hole,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!aligned) ...[
                        Text(
                          'PLACE ID HERE',
                          style: AppTypography.subheading.copyWith(
                            color: Colors.white,
                            letterSpacing: 1.2,
                            shadows: const [
                              Shadow(blurRadius: 8, color: Colors.black54),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        aligned
                            ? 'ID in frame — hold still'
                            : 'Place ID inside the frame',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Rect _holeRect(Size size) {
    const inset = 20.0;
    var width = size.width - inset * 2;
    var height = width / cardAspect;
    if (height > size.height * IdCaptureGuide.maxHeightFraction) {
      height = size.height * IdCaptureGuide.maxHeightFraction;
      width = height * cardAspect;
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }
}

class _CutoutPainter extends CustomPainter {
  const _CutoutPainter({required this.hole, required this.aligned});

  final Rect hole;
  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(16)),
      Paint()
        ..color = aligned ? AppColors.success : AppColors.error
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3.5 : 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.aligned != aligned;
}
