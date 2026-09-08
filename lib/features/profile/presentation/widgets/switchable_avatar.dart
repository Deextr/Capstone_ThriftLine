import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Profile photo that opens account switching when the user has both roles.
class SwitchableAvatar extends StatelessWidget {
  const SwitchableAvatar({
    super.key,
    required this.imageUrl,
    this.name,
    this.size = 90,
    required this.canSwitch,
    this.onSwitch,
  });

  final String imageUrl;
  final String? name;
  final double size;
  final bool canSwitch;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final avatar = ThriftAvatar(imageUrl: imageUrl, name: name, size: size);
    if (!canSwitch || onSwitch == null) return avatar;

    return GestureDetector(
      onTap: onSwitch,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(
                Icons.sync_alt_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
