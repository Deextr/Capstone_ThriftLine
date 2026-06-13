import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/app_provider.dart';
import '../../../../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final app = context.read<AppProvider>();
    if (auth.isAuthenticated) {
      context.go(auth.homeRoute);
    } else if (!app.isOnboardingComplete) {
      context.go(RouteNames.onboarding);
    } else {
      context.go(RouteNames.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront, size: 64, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(AppConstants.appName, style: AppTypography.display.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text('AI-powered thrift marketplace', style: AppTypography.body.copyWith(color: Colors.white70)),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ],
          ),
        ),
      ),
    );
  }
}
