

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';

/// Data class representing a single item in the [CurvedNavigationBar].
class CurvedNavItem {
  const CurvedNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Optional badge widget (e.g. for unread count).
  final Widget? badge;
}

/// A modern curved bottom navigation bar with a floating selected icon.
///
/// The bar has a solid primary-colored background with a concave notch
/// that follows the currently selected tab. The selected icon floats
/// above the bar inside a circular container.
class CurvedNavigationBar extends StatefulWidget {
  const CurvedNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<CurvedNavItem> items;

  @override
  State<CurvedNavigationBar> createState() => _CurvedNavigationBarState();
}

class _CurvedNavigationBarState extends State<CurvedNavigationBar>
    with TickerProviderStateMixin {
  late AnimationController _positionController;
  late Animation<double> _positionAnimation;
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  static const double _barHeight = 62.0;
  static const double _notchRadius = 34.0;
  static const double _notchMargin = 10.0;
  static const double _floatCircleSize = 44.0;
  static const double _floatIconSize = 22.0;
  static const double _iconSize = 23.0;

  // How far above the bar top the floating circle sits
  static const double _floatElevation = 18.0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    // Controls the notch + floating circle horizontal position
    _positionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _positionAnimation = Tween<double>(
      begin: widget.selectedIndex.toDouble(),
      end: widget.selectedIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _positionController,
      curve: Curves.easeInOutCubic,
    ));

    // Controls the floating circle bounce (scale + translate)
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
      value: 1.0, // start fully shown
    );
    _floatAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(covariant CurvedNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedIndex != widget.selectedIndex) {
      // Animate the notch position
      _positionAnimation = Tween<double>(
        begin: oldWidget.selectedIndex.toDouble(),
        end: widget.selectedIndex.toDouble(),
      ).animate(CurvedAnimation(
        parent: _positionController,
        curve: Curves.easeInOutCubic,
      ));
      _positionController.forward(from: 0.0);

      // Bounce the floating icon
      _floatController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  double _getItemCenterX(double screenWidth, double position) {
    final itemWidth = screenWidth / widget.items.length;
    return (position * itemWidth) + (itemWidth / 2);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final totalHeight = _barHeight + bottomPadding;

    return SizedBox(
      height: totalHeight + _floatElevation,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // --- Curved background (painted) ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: totalHeight,
            child: AnimatedBuilder(
              listenable: _positionAnimation,
              builder: (context, _) {
                final screenWidth = MediaQuery.of(context).size.width;
                final centerX = _getItemCenterX(
                  screenWidth,
                  _positionAnimation.value,
                );
                return CustomPaint(
                  size: Size(screenWidth, totalHeight),
                  painter: _CurvedNavBarPainter(
                    notchCenterX: centerX,
                    notchRadius: _notchRadius,
                    notchMargin: _notchMargin,
                    color: AppColors.primary,
                    shadowColor: AppColors.primaryDark.withValues(alpha: 0.35),
                  ),
                );
              },
            ),
          ),

          // --- Inactive icons (sitting on the bar) ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: totalHeight,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  final isSelected = i == widget.selectedIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onTap(i),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isSelected ? 0.0 : 1.0,
                        child: _BarIcon(
                          item: widget.items[i],
                          iconSize: _iconSize,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // --- Floating selected icon (above the notch) ---
          AnimatedBuilder(
            listenable: Listenable.merge([_positionAnimation, _floatAnimation]),
            builder: (context, _) {
              final screenWidth = MediaQuery.of(context).size.width;
              final centerX = _getItemCenterX(
                screenWidth,
                _positionAnimation.value,
              );

              // Bounce animation: scale + slight vertical offset
              final bounceValue = _floatAnimation.value;
              final scale = 0.5 + (bounceValue * 0.5); // 0.5 → 1.0
              final verticalOffset =
                  (1.0 - bounceValue) * 8.0; // starts 8px lower, settles to 0

              return Positioned(
                left: centerX - (_floatCircleSize / 2),
                top: _floatElevation - (_floatCircleSize / 2) + verticalOffset,
                child: Transform.scale(
                  scale: scale,
                  child: _FloatingIcon(
                    item: widget.items[widget.selectedIndex],
                    size: _floatCircleSize,
                    iconSize: _floatIconSize,
                    onTap: () => widget.onTap(widget.selectedIndex),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AnimatedBuilder helper
// ---------------------------------------------------------------------------
class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  final Widget Function(BuildContext context, Widget? child) builder;

  @override
  Widget build(BuildContext context) => builder(context, null);
}

// ---------------------------------------------------------------------------
// Floating circle icon (selected state)
// ---------------------------------------------------------------------------
class _FloatingIcon extends StatelessWidget {
  const _FloatingIcon({
    required this.item,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final CurvedNavItem item;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(
      item.activeIcon,
      size: iconSize,
      color: Colors.white,
    );

    // Badge support
    if (item.badge != null) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(right: -8, top: -6, child: item.badge!),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryDark,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(child: iconWidget),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar icon (inactive state — white icon on colored bar)
// ---------------------------------------------------------------------------
class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.item,
    required this.iconSize,
  });

  final CurvedNavItem item;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(
      item.icon,
      size: iconSize,
      color: Colors.white.withValues(alpha: 0.75),
    );

    if (item.badge != null) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(right: -8, top: -6, child: item.badge!),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(height: 4),
        Text(
          item.label,
          style: AppTypography.caption.copyWith(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter — solid primary bar with animated concave notch
// ---------------------------------------------------------------------------
class _CurvedNavBarPainter extends CustomPainter {
  _CurvedNavBarPainter({
    required this.notchCenterX,
    required this.notchRadius,
    required this.notchMargin,
    required this.color,
    required this.shadowColor,
  });

  final double notchCenterX;
  final double notchRadius;
  final double notchMargin;
  final Color color;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final r = notchRadius + notchMargin;
    final notchDepth = r * 0.75;

    final path = Path();

    // Start top-left
    path.moveTo(0, 0);

    // Approach the notch
    final notchLeft = notchCenterX - r;
    final notchRight = notchCenterX + r;

    // Always draw to the start of the notch, even if it goes off-screen to the left
    path.lineTo(notchLeft, 0);

    // Draw the concave notch
    path.cubicTo(
      notchCenterX - r * 0.55, 0,
      notchCenterX - r * 0.4, notchDepth,
      notchCenterX, notchDepth,
    );
    path.cubicTo(
      notchCenterX + r * 0.4, notchDepth,
      notchCenterX + r * 0.55, 0,
      notchRight, 0,
    );

    // Continue to top-right
    path.lineTo(size.width, 0);

    // Right edge, bottom, left edge
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // Draw shadow first, then fill
    canvas.drawPath(path.shift(const Offset(0, -3)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvedNavBarPainter oldDelegate) =>
      notchCenterX != oldDelegate.notchCenterX ||
      color != oldDelegate.color ||
      notchRadius != oldDelegate.notchRadius;
}
