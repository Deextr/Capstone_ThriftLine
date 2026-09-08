import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../domain/id_image_quality.dart';

/// Full-screen ID-1 cutout with corner guides and a status pill.
class IdCaptureOverlay extends StatelessWidget {
  const IdCaptureOverlay({
    super.key,
    this.status = LiveIdStatus.searching,
    this.capturing = false,
    this.statusMessage,
  });

  final LiveIdStatus status;
  final bool capturing;
  final String? statusMessage;

  static const double cardAspect = IdCaptureGuide.cardAspect;

  static Rect holeRect(Size size) {
    final window = IdImageMetrics.centerCardWindow(
      size.width.round().clamp(8, 16384),
      size.height.round().clamp(8, 16384),
    );
    return Rect.fromLTWH(
      window.x0.toDouble(),
      window.y0.toDouble(),
      window.width.toDouble(),
      window.height.toDouble(),
    );
  }

  Color get _frameColor {
    if (capturing || status == LiveIdStatus.aligned) return AppColors.success;
    if (status == LiveIdStatus.searching) return Colors.white;
    return AppColors.secondary;
  }

  IconData get _icon {
    if (capturing) return Icons.camera_alt_outlined;
    return switch (status) {
      LiveIdStatus.aligned => Icons.check_circle_outline,
      LiveIdStatus.searching => Icons.camera_alt_outlined,
      _ => Icons.warning_amber_rounded,
    };
  }

  String get _message {
    if (statusMessage != null) return statusMessage!;
    if (capturing) return 'Capturing…';
    return LiveIdAssessment(status: status).feedbackMessage;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hole = holeRect(constraints.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _CutoutPainter(hole: hole, color: _frameColor),
              ),
              Positioned.fromRect(
                rect: hole,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: hole.width * 0.86),
                    child: _StatusPill(
                      icon: _icon,
                      color: _frameColor,
                      message: _message,
                      subtitle: !capturing && status == LiveIdStatus.searching
                          ? 'Photo will be taken automatically'
                          : null,
                    ),
                  ),
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
    required this.icon,
    required this.color,
    required this.message,
    this.subtitle,
  });

  final IconData icon;
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CutoutPainter extends CustomPainter {
  const _CutoutPainter({required this.hole, required this.color});

  final Rect hole;
  final Color color;

  static const double _radius = 16;
  static const double _arm = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(_radius)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(_topLeft(hole), paint);
    canvas.drawPath(_topRight(hole), paint);
    canvas.drawPath(_bottomLeft(hole), paint);
    canvas.drawPath(_bottomRight(hole), paint);
  }

  Path _topLeft(Rect hole) {
    return Path()
      ..moveTo(hole.left, hole.top + _arm)
      ..lineTo(hole.left, hole.top + _radius)
      ..quadraticBezierTo(hole.left, hole.top, hole.left + _radius, hole.top)
      ..lineTo(hole.left + _arm, hole.top);
  }

  Path _topRight(Rect hole) {
    return Path()
      ..moveTo(hole.right, hole.top + _arm)
      ..lineTo(hole.right, hole.top + _radius)
      ..quadraticBezierTo(hole.right, hole.top, hole.right - _radius, hole.top)
      ..lineTo(hole.right - _arm, hole.top);
  }

  Path _bottomLeft(Rect hole) {
    return Path()
      ..moveTo(hole.left, hole.bottom - _arm)
      ..lineTo(hole.left, hole.bottom - _radius)
      ..quadraticBezierTo(
        hole.left,
        hole.bottom,
        hole.left + _radius,
        hole.bottom,
      )
      ..lineTo(hole.left + _arm, hole.bottom);
  }

  Path _bottomRight(Rect hole) {
    return Path()
      ..moveTo(hole.right, hole.bottom - _arm)
      ..lineTo(hole.right, hole.bottom - _radius)
      ..quadraticBezierTo(
        hole.right,
        hole.bottom,
        hole.right - _radius,
        hole.bottom,
      )
      ..lineTo(hole.right - _arm, hole.bottom);
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color;
}
