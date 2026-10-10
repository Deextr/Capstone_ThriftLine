import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_users_controller.dart';
import '../../data/admin_users_service.dart';
import '../widgets/admin_marketplace_user_dialogs.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebUsersPage extends StatefulWidget {
  const AdminWebUsersPage({super.key});

  @override
  State<AdminWebUsersPage> createState() => _AdminWebUsersPageState();
}

class _AdminWebUsersPageState extends State<AdminWebUsersPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminUsersController>().scheduleSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminUsersController>();
    final compact = MediaQuery.sizeOf(context).width < 960;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        children: [
          if (controller.noticeMessage != null)
            _Banner(
              message: controller.noticeMessage!,
              error: false,
              onDismiss: controller.clearNotice,
            ),
          if (controller.errorMessage != null)
            _Banner(
              message: controller.errorMessage!,
              error: true,
              onRetry: controller.load,
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
                hintText: 'Search name, email, or username',
                width: 280,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<String?>(
                value: controller.accountType,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All users')),
                  DropdownMenuItem(value: 'buyer', child: Text('Buyers')),
                  DropdownMenuItem(value: 'both', child: Text('Both')),
                ],
                onChanged: controller.setAccountType,
              ),
              AdminFilterDropdown<String?>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'suspended', child: Text('Disabled')),
                  DropdownMenuItem(value: 'banned', child: Text('Banned')),
                ],
                onChanged: controller.setStatusFilter,
              ),
            ],
          ),
          if (compact)
            _UserCards(
              controller: controller,
              onView: _view,
              onDisable: _disable,
            )
          else
            AdminDataTable(
              isLoading: controller.isLoading,
              minWidth: 920,
              emptyTitle: 'No users found',
              emptyMessage: controller.hasActiveFilters
                  ? 'No marketplace accounts match these filters.'
                  : 'Registered buyers and sellers will appear here.',
              onResetFilters: controller.hasActiveFilters
                  ? () {
                      _searchController.clear();
                      controller.resetFilters();
                    }
                  : null,
              columns: const [
                'User',
                'Email',
                'Account type',
                'Account status',
                'Date joined',
                'Actions',
              ],
              columnFlex: const [3, 3, 2, 2, 2, 2],
              onRowTap: [for (final user in controller.rows) () => _view(user)],
              rows: [
                for (final user in controller.rows)
                  [
                    AdminTableApplicantCell(
                      displayName: user.displayName,
                      secondaryLine: user.username.isNotEmpty
                          ? '@${user.username}'
                          : null,
                      avatarName: user.displayName,
                    ),
                    Text(
                      user.email.isEmpty ? '—' : user.email,
                      style: AppTypography.tableBody,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(user.accountTypeLabel, style: AppTypography.tableBody),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MarketplaceStatusBadge(
                        status: user.effectiveAccountStatus,
                      ),
                    ),
                    Text(
                      formatAdminTableDate(user.createdAt),
                      style: AppTypography.tableBody,
                    ),
                    AdminTableActionCell(
                      child: _DisableAction(user: user, onDisable: _disable),
                    ),
                  ],
              ],
            ),
          const SizedBox(height: 16),
          AdminPagination(
            currentPage: controller.page,
            totalItems: controller.total,
            pageSize: controller.pageSize,
            pageSizeOptions: const [10, 25, 50],
            isLoading: controller.isLoading,
            onPageChanged: controller.setPage,
            onPageSizeChanged: controller.setPageSize,
          ),
        ],
      ),
    );
  }

  Future<void> _view(MarketplaceUserRow user) {
    final controller = context.read<AdminUsersController>();
    return showMarketplaceUserDetailDialog(
      context: context,
      user: user,
      loadDetail: () => controller.loadDetail(user.userId),
    );
  }

  Future<void> _disable(MarketplaceUserRow user) {
    if (!user.mayDisable) return Future.value();
    final controller = context.read<AdminUsersController>();
    return showDisableMarketplaceAccountDialog(
      context: context,
      user: user,
      onConfirm: (reason, notes) => controller.disableAccount(
        userId: user.userId,
        reason: reason,
        notes: notes,
      ),
    );
  }
}

class _DisableAction extends StatelessWidget {
  const _DisableAction({required this.user, required this.onDisable});

  final MarketplaceUserRow user;
  final ValueChanged<MarketplaceUserRow> onDisable;

  @override
  Widget build(BuildContext context) {
    final blocked = user.disableBlockedMessage;
    if (user.mayDisable) {
      return TextButton(
        onPressed: () => onDisable(user),
        style: TextButton.styleFrom(
          foregroundColor: Color(0xFF9F1239),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: const Text('Disable account'),
      );
    }
    return Tooltip(
      message: blocked ?? 'This account cannot be disabled.',
      child: Text(
        'Disable unavailable',
        style: TextStyle(
          color: AppColors.textHint,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UserCards extends StatelessWidget {
  const _UserCards({
    required this.controller,
    required this.onView,
    required this.onDisable,
  });

  final AdminUsersController controller;
  final ValueChanged<MarketplaceUserRow> onView;
  final ValueChanged<MarketplaceUserRow> onDisable;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && controller.rows.isEmpty) {
      return AdminTableSkeleton(
        columns: ['User', 'Email', 'Status'],
        rowCount: 4,
      );
    }
    if (controller.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          controller.hasActiveFilters
              ? 'No marketplace accounts match these filters.'
              : 'Registered buyers and sellers will appear here.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        for (final user in controller.rows)
          _UserCard(
            user: user,
            onView: () => onView(user),
            onDisable: () => onDisable(user),
          ),
      ],
    );
  }
}

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.user,
    required this.onView,
    required this.onDisable,
  });

  final MarketplaceUserRow user;
  final VoidCallback onView;
  final VoidCallback onDisable;

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onView,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.03)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      user.displayName,
                      style: AppTypography.tableBodyMedium,
                    ),
                  ),
                  MarketplaceStatusBadge(status: user.effectiveAccountStatus),
                ],
              ),
              SizedBox(height: 4),
              Text(
                user.email.isEmpty ? '—' : user.email,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${user.accountTypeLabel} · Joined ${formatAdminTableDate(user.createdAt)}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 8),
              AdminTableActionCell(
                child: _DisableAction(
                  user: user,
                  onDisable: (_) => widget.onDisable(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.error,
    this.onRetry,
    this.onDismiss,
  });

  final String message;
  final bool error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.primaryDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: AppTypography.body.copyWith(color: color),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          if (onDismiss != null)
            TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}
