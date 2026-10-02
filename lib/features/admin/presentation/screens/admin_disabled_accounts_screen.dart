import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_disabled_accounts_controller.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_review_widgets.dart';

class AdminDisabledAccountsScreen extends StatelessWidget {
  const AdminDisabledAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisabledAccountsController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Disabled accounts'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const AdminDetailSkeleton()
            : controller.errorMessage != null
            ? AdminErrorState(
                message: controller.errorMessage!,
                onRetry: () =>
                    context.read<AdminDisabledAccountsController>().load(),
              )
            : controller.accounts.isEmpty
            ? const AdminEmptyState(
                title: 'No permanently disabled accounts',
                message:
                    'Accounts disabled after repeated Looking For violations will appear here.',
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () =>
                    context.read<AdminDisabledAccountsController>().load(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  itemCount: controller.accounts.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final account = controller.accounts[index];
                    final open = controller.openUserId == account.userId;
                    final history = controller.historyFor(account.userId);
                    final name = account.name.trim().isEmpty
                        ? adminHandle(account.username, account.name)
                        : account.name.trim();
                    return Material(
                      color: AppColors.surface,
                      child: InkWell(
                        onTap: () => context
                            .read<AdminDisabledAccountsController>()
                            .toggle(account.userId),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: AppTypography.body.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    'Permanently disabled',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${accountRoleLabel(account.role)} · ${account.strikeCount} confirmed violations',
                                style: AppTypography.caption,
                              ),
                              if (account.disabledAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Disabled ${formatFullDate(account.disabledAt!)}',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ],
                              if (account.reason.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  account.reason,
                                  style: AppTypography.caption,
                                ),
                              ],
                              if (open) ...[
                                const SizedBox(height: 10),
                                if (history.isEmpty)
                                  Text(
                                    'No violation history loaded.',
                                    style: AppTypography.caption,
                                  )
                                else
                                  for (final item in history)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        'Strike ${item.strikeNumber} · ${item.postTitle ?? 'Request'} · ${formatFullDate(item.createdAt)}',
                                        style: AppTypography.caption,
                                      ),
                                    ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
