import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_disputes_controller.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_review_widgets.dart';

class AdminDisputesQueueScreen extends StatelessWidget {
  const AdminDisputesQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Delivery Problems'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AdminFilterBar(
                  value: controller.filter,
                  onChanged: (filter) =>
                      context.read<AdminDisputesController>().setFilter(filter),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<AdminDisputesController>().load(),
                child: controller.isLoading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : controller.errorMessage != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          AdminErrorState(
                            message: controller.errorMessage!,
                            onRetry: () =>
                                context.read<AdminDisputesController>().load(),
                          ),
                        ],
                      )
                    : controller.disputes.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          AdminEmptyState(
                            title: controller.filter == AdminQueueFilter.open
                                ? 'No delivery problems waiting for review.'
                                : 'No closed delivery problems yet.',
                            message: controller.filter == AdminQueueFilter.open
                                ? 'Buyer delivery issues will appear here.'
                                : 'Closed cases will appear here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                        itemCount: controller.disputes.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                controller.filter == AdminQueueFilter.open
                                    ? '${controller.disputes.length} require review'
                                    : '${controller.disputes.length} closed',
                                style: AppTypography.caption,
                              ),
                            );
                          }
                          final dispute = controller.disputes[index - 1];
                          return AdminQueueItem(
                            title: dispute.reason.label,
                            status: dispute.status,
                            statusLabel: disputeStatusLabel(dispute.status),
                            lines: [
                              if (dispute.orderNumber != null)
                                'Order #${dispute.orderNumber}',
                              'Buyer: ${adminHandle(dispute.buyerUsername, dispute.buyerDisplayName)}',
                            ],
                            meta: formatCompactDate(dispute.createdAt),
                            actionLabel: 'View case',
                            onTap: () => _open(context, dispute.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String disputeId) async {
    await context.push(RouteNames.adminDisputeDetailFor(disputeId));
    if (context.mounted) {
      await context.read<AdminDisputesController>().load();
    }
  }
}
