import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/my_confirmed_violations_controller.dart';
import '../../data/confirmed_violation_labels.dart';
import '../../domain/confirmed_violation.dart';
import '../widgets/confirmed_violations_filter_sheet.dart';

class MyConfirmedViolationsScreen extends StatefulWidget {
  const MyConfirmedViolationsScreen({super.key});

  @override
  State<MyConfirmedViolationsScreen> createState() =>
      _MyConfirmedViolationsScreenState();
}

class _MyConfirmedViolationsScreenState
    extends State<MyConfirmedViolationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MyConfirmedViolationsController>().load();
    });
  }

  void _openFilters(MyConfirmedViolationsController controller) {
    ConfirmedViolationsFilterSheet.show(
      context,
      initialCategory: controller.categoryFilter,
      initialPenalty: controller.penaltyFilter,
      initialDateFrom: controller.dateFrom,
      initialDateTo: controller.dateTo,
      onApply: (category, penalty, from, to) {
        controller.applyFilters(
          category: category,
          penalty: penalty,
          dateFrom: from,
          dateTo: to,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyConfirmedViolationsController>();
    final initialLoad = controller.isLoading && !controller.hasAnyViolations;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirmed Violations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: initialLoad
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : controller.errorMessage != null && !controller.hasAnyViolations
            ? _ErrorState(
                message: controller.errorMessage!,
                onRetry: () => controller.load(),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => controller.load(showSpinner: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(
                          'These are violations confirmed after an admin review '
                          'or automated enforcement. Pending reports are not listed here.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (controller.hasAnyViolations)
                      SliverToBoxAdapter(
                        child: _ListHeader(
                          controller: controller,
                          onFilterTap: () => _openFilters(controller),
                        ),
                      ),
                    if (!controller.hasAnyViolations)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: const _EmptyState(),
                      )
                    else if (controller.visibleItems.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _NoMatchState(
                          onClear: controller.resetFilters,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: controller.visibleItems.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = controller.visibleItems[index];
                            return _ViolationCard(item: item);
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.controller, required this.onFilterTap});

  final MyConfirmedViolationsController controller;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    final total = controller.totalCount;
    final visible = controller.visibleItems.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              controller.filtersActive
                  ? '$visible matching · $total total'
                  : '$total violation${total == 1 ? '' : 's'}',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: onFilterTap,
            icon: const Icon(Icons.filter_list_rounded, size: 20),
            label: const Text('Filter'),
          ),
          if (controller.filtersActive)
            IconButton(
              tooltip: 'Clear filters',
              onPressed: controller.resetFilters,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({required this.item});

  final ConfirmedViolationSummary item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          RouteNames.confirmedViolationDetailFor(item.source, item.recordId),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                confirmedViolationTypeHeading(item),
                style: AppTypography.subheading.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.referenceTitle,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactDate(item.confirmedAt.toLocal()),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    confirmedViolationPenaltySummary(item),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'No confirmed violations',
              style: AppTypography.subheading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'When a violation is officially confirmed against your account, '
              'it will appear here with the date and any penalty applied.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No violations match these filters',
              style: AppTypography.subheading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
