import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Desktop-first case review shell (order disputes). Uses full admin content width.
class AdminWideCaseDetailPage extends StatelessWidget {
  const AdminWideCaseDetailPage({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.header,
    required this.main,
    required this.sidebar,
    this.maxWidth = 1280,
    this.sidebarWidth = 300,
    this.twoColumnBreakpoint = 960,
  });

  final String backLabel;
  final VoidCallback onBack;
  final Widget header;
  final Widget main;
  final Widget sidebar;
  final double maxWidth;
  final double sidebarWidth;
  final double twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= twoColumnBreakpoint;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: onBack,
                                icon: Icon(Icons.arrow_back, size: 18),
                                label: Text(backLabel),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            header,
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                      sliver: SliverToBoxAdapter(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 68, child: main),
                                  const SizedBox(width: 28),
                                  SizedBox(width: sidebarWidth, child: sidebar),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  main,
                                  const SizedBox(height: 28),
                                  sidebar,
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-rail panel surface for decisions and summaries.
class AdminCaseSidebarPanel extends StatelessWidget {
  const AdminCaseSidebarPanel({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
