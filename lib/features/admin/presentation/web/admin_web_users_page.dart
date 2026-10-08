import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/admin_users_controller.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebUsersPage extends StatefulWidget {
  const AdminWebUsersPage({super.key});

  @override
  State<AdminWebUsersPage> createState() => _AdminWebUsersPageState();
}

class _AdminWebUsersPageState extends State<AdminWebUsersPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminUsersController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          AdminPageHeader(
            title: 'User Management',
            subtitle:
                'View user accounts, roles, trust scores, and activity across the marketplace.',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.push(RouteNames.adminDisabledAccounts),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Disabled Accounts'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.isLoading
                    ? null
                    : () => controller.load(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),

          // Filters Bar
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
            },
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search by name, email, @username...',
                width: 290,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<String?>(
                value: controller.roleFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Roles')),
                  DropdownMenuItem(value: 'buyer', child: Text('Buyer')),
                  DropdownMenuItem(value: 'seller', child: Text('Seller')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: controller.setRoleFilter,
              ),
              AdminFilterDropdown<String?>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'banned', child: Text('Banned')),
                ],
                onChanged: controller.setStatusFilter,
              ),
            ],
          ),

          if (controller.errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.errorMessage!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],

          // Data Table
          AdminDataTable(
            isLoading: controller.isLoading,
            emptyTitle: 'No users found',
            emptyMessage: controller.hasActiveFilters
                ? 'No users match your active filters. Try adjusting your search.'
                : 'Users will appear here once registered.',
            onResetFilters: controller.hasActiveFilters
                ? () {
                    _searchController.clear();
                    controller.resetFilters();
                  }
                : null,
            columns: const [
              'User',
              'Email',
              'Role',
              'Status',
              'Trust',
              'Rating',
              'Joined',
              'Last Active',
            ],
            columnFlex: const [3, 3, 1, 1, 1, 1, 2, 2],
            rows: [
              for (final user in controller.rows)
                [
                  AdminTableApplicantCell(
                    displayName: user.fullName.isNotEmpty
                        ? user.fullName
                        : user.username,
                    secondaryLine: user.username.isNotEmpty
                        ? '@${user.username}'
                        : null,
                    avatarName: user.fullName.isNotEmpty
                        ? user.fullName
                        : user.username,
                  ),
                  AdminTableCellText(
                    primary: user.email,
                    primaryStyle: AppTypography.tableBody,
                  ),
                  AdminTableCellText(
                    primary: user.role.name.toUpperCase(),
                    primaryStyle: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: user.role.name == 'admin'
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  AdminStatusBadge(status: user.accountStatus),
                  Text(
                    user.trustScore.toStringAsFixed(0),
                    style: AppTypography.tableBodyMedium,
                  ),
                  Text(
                    user.rating.toStringAsFixed(1),
                    style: AppTypography.tableBody,
                  ),
                  AdminTableDateCell(dateTime: user.createdAt),
                  user.lastActiveAt != null
                      ? AdminTableDateCell(dateTime: user.lastActiveAt!)
                      : Text(
                          '—',
                          style: AppTypography.tableBody.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                ],
            ],
          ),

          const SizedBox(height: 16),

          // Standardized Pagination
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
}
