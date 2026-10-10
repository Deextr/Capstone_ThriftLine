import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_bidding_violations_controller.dart';
import '../../data/admin_bidding_violations_service.dart';
import '../../domain/auction_bidding_violations.dart';
import '../widgets/admin_bidding_violation_detail_dialog.dart';
import '../widgets/admin_marketplace_user_dialogs.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebBiddingViolationsPage extends StatefulWidget {
  const AdminWebBiddingViolationsPage({super.key});

  @override
  State<AdminWebBiddingViolationsPage> createState() =>
      _AdminWebBiddingViolationsPageState();
}

class _AdminWebBiddingViolationsPageState
    extends State<AdminWebBiddingViolationsPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminBiddingViolationsController>().load();
    });
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminBiddingViolationsController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(BiddingViolatorSummary buyer) {
    final controller = context.read<AdminBiddingViolationsController>();
    showBiddingViolationDetailDialog(
      context: context,
      buyer: buyer,
      loadHistory: () => controller.loadHistory(buyer.userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminBiddingViolationsController>();
    final compact = MediaQuery.sizeOf(context).width < 960;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        children: [
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.error!,
                          style: AppTypography.body,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
            },
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search name, email, username, or user ID',
                width: 300,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<ViolationCountFilter>(
                value: controller.violationCountFilter,
                items: const [
                  DropdownMenuItem(
                    value: ViolationCountFilter.all,
                    child: Text('All violation counts'),
                  ),
                  DropdownMenuItem(
                    value: ViolationCountFilter.first,
                    child: Text('First violation'),
                  ),
                  DropdownMenuItem(
                    value: ViolationCountFilter.second,
                    child: Text('Second violation'),
                  ),
                  DropdownMenuItem(
                    value: ViolationCountFilter.threeOnly,
                    child: Text('Third violation'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setViolationCountFilter(value);
                },
              ),
              AdminFilterDropdown<BiddingRestrictionStatusFilter>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(
                    value: BiddingRestrictionStatusFilter.all,
                    child: Text('All account statuses'),
                  ),
                  DropdownMenuItem(
                    value: BiddingRestrictionStatusFilter.active,
                    child: Text('Active'),
                  ),
                  DropdownMenuItem(
                    value: BiddingRestrictionStatusFilter.restricted,
                    child: Text('Restricted'),
                  ),
                  DropdownMenuItem(
                    value: BiddingRestrictionStatusFilter.banned,
                    child: Text('Banned'),
                  ),
                  DropdownMenuItem(
                    value: BiddingRestrictionStatusFilter.needsAttention,
                    child: Text('Restricted or banned'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setStatusFilter(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (compact)
            _MobileList(controller: controller, onViewDetails: _openDetails)
          else
            AdminDataTable(
              isLoading: controller.isLoading,
              minWidth: 920,
              emptyTitle: 'No records',
              emptyMessage: controller.hasActiveFilters
                  ? 'No buyers match these filters.'
                  : 'No records to display.',
              onResetFilters: controller.hasActiveFilters
                  ? () {
                      _searchController.clear();
                      controller.resetFilters();
                    }
                  : null,
              columns: const [
                'Buyer',
                'Violations',
                'Latest violation',
                'Account status',
                'Action',
              ],
              columnFlex: const [3, 2, 2, 2, 2],
              rows: [
                for (final row in controller.rows)
                  [
                    AdminTableApplicantCell(
                      displayName: row.displayName,
                      secondaryLine: row.username.isNotEmpty
                          ? '@${row.username}'
                          : null,
                      avatarName: row.displayName,
                    ),
                    Text(
                      formatOrdinalViolationCount(row.violationCount),
                      style: AppTypography.tableBody,
                    ),
                    Text(
                      row.latestViolationAt == null
                          ? '—'
                          : formatAdminTableDate(row.latestViolationAt!),
                      style: AppTypography.tableBody,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusCell(summary: row),
                    ),
                    TextButton(
                      onPressed: () => _openDetails(row),
                      child: const Text('View details'),
                    ),
                  ],
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.summary});

  final BiddingViolatorSummary summary;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final enforcement = summary.enforcementStatusAt(now);

    if (enforcement == BiddingEnforcementStatus.banned) {
      return const MarketplaceStatusBadge(status: 'banned');
    }

    if (enforcement == BiddingEnforcementStatus.restricted &&
        summary.restrictedUntil != null) {
      final remaining = formatBiddingRestrictionRemaining(
        summary.restrictedUntil!,
        now: now,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _RestrictedBadge(label: remaining.isEmpty ? 'Restricted' : remaining),
        ],
      );
    }

    return const MarketplaceStatusBadge(status: 'active');
  }
}

class _RestrictedBadge extends StatelessWidget {
  const _RestrictedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF92400E).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(
          color: const Color(0xFF92400E),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MobileList extends StatelessWidget {
  const _MobileList({required this.controller, required this.onViewDetails});

  final AdminBiddingViolationsController controller;
  final void Function(BiddingViolatorSummary buyer) onViewDetails;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && controller.rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          controller.hasActiveFilters
              ? 'No buyers match these filters.'
              : 'No records to display.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: [
        for (final row in controller.rows)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(row.displayName),
              subtitle: Text(
                '${formatOrdinalViolationCount(row.violationCount)} · '
                '${row.latestViolationAt == null ? '—' : formatAdminTableDate(row.latestViolationAt!)}',
              ),
              trailing: TextButton(
                onPressed: () => onViewDetails(row),
                child: const Text('Details'),
              ),
            ),
          ),
      ],
    );
  }
}
