import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Official ThriftLine mark, sized for auth screens over the video backdrop.
class AuthBrandLogo extends StatelessWidget {
  const AuthBrandLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 36,
            spreadRadius: -6,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.22),
        child: Image.asset(
          'assets/images/thriftline-logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Soft teal-tinted veil so auth UI stays readable over the looping video.
class AuthVideoScrim extends StatelessWidget {
  const AuthVideoScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x59000000),
            Color(0x330D9488),
            Color(0x73000000),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
    );
  }
}
