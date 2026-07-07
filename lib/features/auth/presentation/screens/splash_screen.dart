import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/app_provider.dart';
import '../../../../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────────
  late final AnimationController _introController;
  late final AnimationController _pulseController;

  // ── Intro animations (logo + text) ──────────────────────────────────────
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;

  // ── Pulse animation (subtle breathe while auth resolves) ─────────────────
  late final Animation<double> _pulsScale;

  // ── Progress bar ─────────────────────────────────────────────────────────
  late final AnimationController _progressController;
  late final Animation<double> _progressValue;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    // ── Intro controller: 1 200 ms total ──
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Logo: fade 0→1 and elastic scale 0.5→1.0 in first 700 ms
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.60, curve: Curves.elasticOut),
      ),
    );

    // App name text: slides up from 20px below and fades in, starts at 500 ms
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.42, 0.85, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.42, 0.85, curve: Curves.easeOut),
      ),
    );

    // ── Pulse controller: continuous subtle breathe ──
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulsScale = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // ── Progress bar: 0→1 over 1 800 ms ──
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _progressValue = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _startSequence() async {
    // Kick off intro + progress simultaneously
    _introController.forward();
    _progressController.forward();

    // Wait for the minimum splash display time
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
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
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ── Dark-teal → lighter-teal gradient background ──────────────────
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF065F56), // very dark teal
              Color(0xFF0D9488), // AppColors.primary
              Color(0xFF14B8A6), // lighter teal
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ── Radial glow decoration (depth) ────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, -0.2),
                      radius: 0.75,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Main content ──────────────────────────────────────────
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with intro + pulse animation stacked
                    AnimatedBuilder(
                      animation:
                          Listenable.merge([_introController, _pulseController]),
                      builder: (_, child) {
                        return Opacity(
                          opacity: _logoOpacity.value,
                          child: Transform.scale(
                            // Pulse only starts after intro is complete
                            scale: _introController.isCompleted
                                ? _pulsScale.value
                                : _logoScale.value,
                            child: _LogoBadge(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // App name + tagline slide-up
                    AnimatedBuilder(
                      animation: _introController,
                      builder: (_, child) {
                        return FadeTransition(
                          opacity: _textOpacity,
                          child: SlideTransition(
                            position: _textSlide,
                            child: Column(
                              children: [
                                Text(
                                  'ThriftLine',
                                  style: AppTypography.display.copyWith(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Buy & sell pre-loved fashion',
                                  style: AppTypography.body.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 14,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Thin progress bar at the bottom ──────────────────────
              Positioned(
                bottom: 48,
                left: 56,
                right: 56,
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (_, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: _progressValue.value,
                            minHeight: 2.5,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.20),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Badge — white frosted circle containing the ThriftLine logo image
// ─────────────────────────────────────────────────────────────────────────────

class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.35),
            blurRadius: 50,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Image.asset(
          'assets/images/thriftline-logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
