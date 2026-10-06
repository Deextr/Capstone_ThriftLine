import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_users_controller.dart';
import 'admin_web_table.dart';

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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search users',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: controller.setSearch,
                ),
              ),
              DropdownButton<String?>(
                value: controller.roleFilter,
                hint: const Text('Role'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All roles')),
                  DropdownMenuItem(value: 'buyer', child: Text('Buyer')),
                  DropdownMenuItem(value: 'seller', child: Text('Seller')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: controller.setRoleFilter,
              ),
              DropdownButton<String?>(
                value: controller.statusFilter,
                hint: const Text('Status'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'banned', child: Text('Banned')),
                ],
                onChanged: controller.setStatusFilter,
              ),
              TextButton(
                onPressed: () => controller.setSearch(_searchController.text),
                child: const Text('Search'),
              ),
              TextButton(
                onPressed: () => context.push(RouteNames.adminDisabledAccounts),
                child: const Text('Disabled accounts'),
              ),
            ],
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.errorMessage!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          AdminWebTable(
            isLoading: controller.isLoading,
            emptyMessage: 'No users found for this filter.',
            columns: const [
              'User',
              'Email',
              'Role',
              'Status',
              'Trust',
              'Rating',
              'Joined',
              'Last active',
            ],
            rows: [
              for (final user in controller.rows)
                [
                  Text(user.fullName.isNotEmpty ? user.fullName : user.username),
                  Text(user.email),
                  Text(user.role.name),
                  Text(user.accountStatus),
                  Text(user.trustScore.toStringAsFixed(0)),
                  Text(user.rating.toStringAsFixed(1)),
                  Text(formatFullDate(user.createdAt)),
                  Text(
                    user.lastActiveAt != null
                        ? formatFullDate(user.lastActiveAt!)
                        : '—',
                  ),
                ],
            ],
          ),
          const SizedBox(height: 16),
          _Pager(
            page: controller.page,
            total: controller.total,
            pageSize: AdminUsersController.pageSize,
            onPage: controller.setPage,
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = (total / pageSize).ceil().clamp(1, 9999);
    return Row(
      children: [
        Text('Page ${page + 1} of $pages ($total total)'),
        const Spacer(),
        IconButton(
          onPressed: page > 0 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          onPressed: page + 1 < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
