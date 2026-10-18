import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_accounts_controller.dart';
import '../../data/admin_account_models.dart';
import '../widgets/admin_marketplace_user_dialogs.dart';
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
                  DropdownMenuItem(value: 'inactive', child: Text('Disabled')),
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
                onDisable: _disableAccount,
                onEnable: _enableAccount,
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
                'Actions',
              ],
              rows: [
                for (final account in controller.rows)
                  [
                    AdminTableApplicantCell(
                      displayName: account.fullName,
                      secondaryLine: account.roleLabel,
                      avatarName: account.fullName,
                    ),
                    Text(account.email, style: AppTypography.tableBody),
                    Text(account.roleLabel, style: AppTypography.tableBody),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MarketplaceStatusBadge(
                        status: account.statusBadgeKey,
                      ),
                    ),
                    Text(
                      formatAdminTableDate(account.createdAt),
                      style: AppTypography.tableBody,
                    ),
                    AdminTableActionCell(
                      child: _AdminAccountActions(
                        account: account,
                        onDisable: _disableAccount,
                        onEnable: _enableAccount,
                      ),
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

  Future<void> _openAccountDetail(AdminAccountRecord account) {
    final controller = context.read<AdminAccountsController>();
    return showAdminAccountDetailDialog(
      context: context,
      account: account,
      controller: controller,
      onDisable: _disableAccount,
      onEnable: _enableAccount,
    );
  }

  Future<void> _disableAccount(AdminAccountRecord account) async {
    if (!account.canDeactivate) return;
    final confirmed = await _confirmAccountAccessChange(
      context,
      title: 'Disable admin account',
      message:
          'Disable ${account.fullName}? They will lose access to this admin portal immediately. Past decisions stay on record.',
      action: 'Disable account',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<AdminAccountsController>().setActive(
      account,
      active: false,
    );
  }

  Future<void> _enableAccount(AdminAccountRecord account) async {
    if (!account.canActivate) return;
    final confirmed = await _confirmAccountAccessChange(
      context,
      title: 'Enable admin account',
      message:
          'Enable ${account.fullName}? They can sign in to this admin portal again.',
      action: 'Enable account',
    );
    if (!confirmed || !mounted) return;
    await context.read<AdminAccountsController>().setActive(
      account,
      active: true,
    );
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

Future<bool> _confirmAccountAccessChange(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
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
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onTap,
    required this.onDisable,
    required this.onEnable,
  });

  final AdminAccountRecord account;
  final VoidCallback onTap;
  final Future<void> Function(AdminAccountRecord account) onDisable;
  final Future<void> Function(AdminAccountRecord account) onEnable;

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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(account.roleLabel),
                  MarketplaceStatusBadge(status: account.statusBadgeKey),
                ],
              ),
              const SizedBox(height: 8),
              _AdminAccountActions(
                account: account,
                onDisable: onDisable,
                onEnable: onEnable,
              ),
              const SizedBox(height: 8),
              Text(
                'Created ${formatAdminTableDate(account.createdAt)}',
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
  required AdminAccountsController controller,
  required Future<void> Function(AdminAccountRecord account) onDisable,
  required Future<void> Function(AdminAccountRecord account) onEnable,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AdminAccountDetailDialog(
        account: account,
        controller: controller,
        onDisable: onDisable,
        onEnable: onEnable,
      );
    },
  );
}

class _AdminAccountDetailDialog extends StatelessWidget {
  const _AdminAccountDetailDialog({
    required this.account,
    required this.controller,
    required this.onDisable,
    required this.onEnable,
  });

  final AdminAccountRecord account;
  final AdminAccountsController controller;
  final Future<void> Function(AdminAccountRecord account) onDisable;
  final Future<void> Function(AdminAccountRecord account) onEnable;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Administrator details',
                  style: AppTypography.subheading,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          content: SizedBox(
            width: width < 560 ? width : 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThriftAvatar(
                        imageUrl: '',
                        name: account.fullName,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.fullName,
                              style: AppTypography.tableBodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              account.email,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MarketplaceStatusBadge(status: account.statusBadgeKey),
                      _AdminMetaChip(label: account.roleLabel),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Profile',
                    style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AdminDetailRow(
                    label: 'Email',
                    value: account.email,
                  ),
                  _AdminDetailRow(
                    label: 'Role',
                    value: account.roleLabel,
                  ),
                  _AdminDetailRow(
                    label: 'Portal status',
                    value: account.statusLabel,
                  ),
                  _AdminDetailRow(
                    label: 'Created',
                    value: formatAdminTableDate(account.createdAt),
                  ),
                  _AdminDetailRow(
                    label: 'Last sign-in',
                    value: account.lastSignInAt == null
                        ? 'No successful sign-in yet'
                        : formatAdminTableDateTime(account.lastSignInAt!),
                  ),
                  if (account.isSuperAdmin) ...[
                    const SizedBox(height: 12),
                    _AdminNotice(
                      message:
                          'Super Admin accounts cannot be disabled from this screen.',
                    ),
                  ] else if (account.displayStatus == 'invited') ...[
                    const SizedBox(height: 12),
                    _AdminNotice(
                      message:
                          'This administrator has a pending invitation. Resend or revoke the invite below.',
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Account access',
                    style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AdminAccountActions(
                    account: account,
                    onDisable: (record) async {
                      await onDisable(record);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    onEnable: (record) async {
                      await onEnable(record);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  if (account.canResendInvite || account.canRevokeInvite) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Invitation',
                      style: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (account.canResendInvite)
                          OutlinedButton(
                            onPressed: controller.isSaving
                                ? null
                                : () async {
                                    await controller.resend(account);
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            child: const Text('Resend invitation'),
                          ),
                        if (account.canRevokeInvite)
                          TextButton(
                            onPressed: controller.isSaving
                                ? null
                                : () async {
                                    final confirmed =
                                        await _confirmAccountAccessChange(
                                      context,
                                      title: 'Revoke invitation',
                                      message:
                                          'Revoke the invitation for ${account.fullName}? The link will stop working.',
                                      action: 'Revoke',
                                      destructive: true,
                                    );
                                    if (!confirmed || !context.mounted) {
                                      return;
                                    }
                                    await controller.revoke(account);
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                            ),
                            child: const Text('Revoke invitation'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _AdminAccountActions extends StatelessWidget {
  const _AdminAccountActions({
    required this.account,
    required this.onDisable,
    required this.onEnable,
  });

  final AdminAccountRecord account;
  final Future<void> Function(AdminAccountRecord account) onDisable;
  final Future<void> Function(AdminAccountRecord account) onEnable;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (account.canDeactivate)
          TextButton(
            onPressed: () async => onDisable(account),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF9F1239),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Disable account'),
          )
        else if (account.displayStatus == 'active' && account.isSuperAdmin)
          Text(
            'Disable unavailable',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (account.canActivate)
          TextButton(
            onPressed: () async => onEnable(account),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Re-enable account'),
          ),
      ],
    );
  }
}

class _AdminDetailRow extends StatelessWidget {
  const _AdminDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _AdminMetaChip extends StatelessWidget {
  const _AdminMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: AppTypography.caption.copyWith(height: 1.4),
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
