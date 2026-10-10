import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_accounts_controller.dart';
import '../../data/admin_account_models.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebAccountsPage extends StatefulWidget {
  const AdminWebAccountsPage({super.key});

  @override
  State<AdminWebAccountsPage> createState() => _AdminWebAccountsPageState();
}

class _AdminWebAccountsPageState extends State<AdminWebAccountsPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminAccountsController>().load();
    });
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminAccountsController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminAccountsController>();
    final compact =
        MediaQuery.sizeOf(context).width < AppConstants.breakpointDesktop;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AdminGradientButton(
              label: 'Create Admin',
              icon: Icons.person_add_alt_1,
              onPressed: controller.isSaving ? null : () => _create(controller),
            ),
          ),
          const SizedBox(height: 16),
          if (controller.errorMessage != null)
            _Banner(message: controller.errorMessage!, error: true),
          if (controller.successMessage != null)
            _Banner(message: controller.successMessage!, error: false),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
            },
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search by name or email',
                width: 280,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<String?>(
                value: controller.roleFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All roles')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(
                    value: 'super_admin',
                    child: Text('Super Admin'),
                  ),
                ],
                onChanged: controller.setRoleFilter,
              ),
              AdminFilterDropdown<String?>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  DropdownMenuItem(value: 'invited', child: Text('Invited')),
                ],
                onChanged: controller.setStatusFilter,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.isLoading && controller.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No administrator accounts match.')),
            )
          else if (compact)
            ...controller.rows.map(
              (account) => _AccountCard(
                account: account,
                onTap: () => _openAccountDetail(account),
              ),
            )
          else
            AdminDataTable(
              isLoading: controller.isLoading,
              minWidth: 860,
              columnFlex: const [3, 3, 2, 2, 2, 2],
              onRowTap: [
                for (final account in controller.rows)
                  () => _openAccountDetail(account),
              ],
              columns: const [
                'Name',
                'Email',
                'Role',
                'Status',
                'Created',
                'Last sign-in',
              ],
              rows: [
                for (final account in controller.rows)
                  [
                    Text(
                      account.fullName,
                      style: AppTypography.tableBodyMedium,
                    ),
                    Text(account.email, style: AppTypography.tableBody),
                    Text(account.roleLabel, style: AppTypography.tableBody),
                    _StatusChip(status: account.displayStatus),
                    Text(
                      formatAdminTableDate(account.createdAt),
                      style: AppTypography.tableBody,
                    ),
                    Text(
                      account.lastSignInAt == null
                          ? '—'
                          : formatAdminTableDateTime(account.lastSignInAt!),
                      style: AppTypography.tableBody,
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

  Widget _count(
    AdminAccountsController controller,
    String label,
    int count,
    String? status,
  ) {
    return SizedBox(
      width: 180,
      child: AdminStatCard(
        label: label,
        count: count,
        icon: Icons.badge_outlined,
        isSelected: controller.statusFilter == status && status != null,
        onTap: status == null
            ? null
            : () => controller.setStatusFilter(
                controller.statusFilter == status ? null : status,
              ),
      ),
    );
  }

  Future<void> _openAccountDetail(AdminAccountRecord account) {
    return showAdminAccountDetailDialog(context: context, account: account);
  }

  Future<void> _create(AdminAccountsController controller) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final formKey = GlobalKey<FormState>();
    AdminInviteResult? pending;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Create Admin'),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'The new account is an Admin. They set a password from the invitation email and sign in on this portal.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.length < 2) return 'Enter a full name.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: email,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (!isAdminInviteEmail(
                            normalizeAdminEmail(value ?? ''),
                          )) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Role'),
                        subtitle: Text('Admin'),
                      ),
                      if (pending != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          pending!.message ?? adminInvitePendingMessage,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                if (pending?.canResend == true)
                  TextButton(
                    onPressed: controller.isSaving
                        ? null
                        : () async {
                            final result = await controller.resend(
                              AdminAccountRecord(
                                userId: '',
                                fullName: name.text.trim(),
                                email: normalizeAdminEmail(email.text),
                                role: 'admin',
                                accountStatus: 'active',
                                displayStatus: 'invited',
                                createdAt: DateTime.now(),
                                invitationId: pending!.invitationId,
                                invitationStatus: 'pending',
                              ),
                            );
                            if (result.ok && dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                    child: const Text('Resend invitation'),
                  ),
                FilledButton(
                  onPressed: controller.isSaving
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) return;
                          final result = await controller.create(
                            fullName: name.text,
                            email: email.text,
                          );
                          if (result.ok && dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                            return;
                          }
                          setDialogState(() => pending = result);
                        },
                  child: const Text('Send invitation'),
                ),
              ],
            );
          },
        );
      },
    );
    name.dispose();
    email.dispose();
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.onTap});

  final AdminAccountRecord account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.fullName,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(account.email, style: AppTypography.caption),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(account.roleLabel),
                  _StatusChip(status: account.displayStatus),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Created ${formatAdminTableDate(account.createdAt)}',
                style: AppTypography.caption,
              ),
              Text(
                account.lastSignInAt == null
                    ? 'No sign-in yet'
                    : 'Last sign-in ${formatAdminTableDateTime(account.lastSignInAt!)}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAdminAccountDetailDialog({
  required BuildContext context,
  required AdminAccountRecord account,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AdminAccountDetailDialog(account: account);
    },
  );
}

class _AdminAccountDetailDialog extends StatelessWidget {
  const _AdminAccountDetailDialog({required this.account});

  final AdminAccountRecord account;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminAccountsController>();

    return AlertDialog(
      title: Text(account.fullName),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.email, style: AppTypography.body),
            const SizedBox(height: 12),
            Text(
              '${account.roleLabel} · ${account.statusLabel}',
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Created ${formatAdminTableDate(account.createdAt)}',
              style: AppTypography.caption,
            ),
            Text(
              account.lastSignInAt == null
                  ? 'No successful sign-in yet'
                  : 'Last sign-in ${formatAdminTableDateTime(account.lastSignInAt!)}',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (account.canResendInvite)
          TextButton(
            onPressed: controller.isSaving
                ? null
                : () async {
                    await controller.resend(account);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Resend invitation'),
          ),
        if (account.canRevokeInvite)
          TextButton(
            onPressed: controller.isSaving
                ? null
                : () async {
                    final confirmed = await _confirm(
                      context,
                      title: 'Revoke invitation',
                      message:
                          'Revoke the invitation for ${account.fullName}? The link will stop working.',
                      action: 'Revoke',
                    );
                    if (!confirmed || !context.mounted) return;
                    await controller.revoke(account);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Revoke invitation'),
          ),
        if (account.canDeactivate)
          TextButton(
            onPressed: controller.isSaving
                ? null
                : () async {
                    final confirmed = await _confirm(
                      context,
                      title: 'Deactivate administrator',
                      message:
                          'Deactivate ${account.fullName}? They lose admin access immediately. Past decisions stay on record.',
                      action: 'Deactivate',
                    );
                    if (!confirmed || !context.mounted) return;
                    await controller.setActive(account, active: false);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Deactivate'),
          ),
        if (account.canActivate)
          FilledButton(
            onPressed: controller.isSaving
                ? null
                : () async {
                    final confirmed = await _confirm(
                      context,
                      title: 'Activate administrator',
                      message:
                          'Activate ${account.fullName}? They can sign in to this portal again.',
                      action: 'Activate',
                    );
                    if (!confirmed || !context.mounted) return;
                    await controller.setActive(account, active: true);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Activate'),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.success,
      'inactive' => AppColors.error,
      'invited' => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      'active' => 'Active',
      'inactive' => 'Inactive',
      'invited' => 'Invited',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.success;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: AppTypography.body),
    );
  }
}
