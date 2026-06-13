import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class OnboardingPage {
  const OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

abstract final class OnboardingPages {
  static const slides = [
    OnboardingPage(
      title: 'Discover Hidden Gems',
      subtitle: 'AI-powered search helps you find exactly what you\'re looking for in seconds.',
      icon: Icons.auto_awesome,
      color: AppColors.primary,
    ),
    OnboardingPage(
      title: 'Bid & Win',
      subtitle: 'Place bids on unique thrift finds and win amazing deals on pre-loved fashion.',
      icon: Icons.gavel,
      color: AppColors.secondary,
    ),
    OnboardingPage(
      title: 'Sell Your Thrifts',
      subtitle: 'List your pre-loved items easily and reach buyers across Metro Manila.',
      icon: Icons.sell_outlined,
      color: AppColors.success,
    ),
  ];
}
