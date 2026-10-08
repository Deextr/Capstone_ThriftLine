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
import '../widgets/admin_ui_components.dart' hide AdminFilterBar;

class AdminDisputesQueueScreen extends StatefulWidget {
  const AdminDisputesQueueScreen({super.key});

  @override
  State<AdminDisputesQueueScreen> createState() =>
      _AdminDisputesQueueScreenState();
}

class _AdminDisputesQueueScreenState extends State<AdminDisputesQueueScreen> {
  int _page = 0;
  int _pageSize = 10;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesController>();
    final open = controller.filter == AdminQueueFilter.open;
    final total = controller.disputes.length;
    final maxPage = total <= 0 ? 0 : (total - 1) ~/ _pageSize;
    final safePage = _page.clamp(0, maxPage);
    final startIndex = safePage * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, total);
    final pageDisputes = total == 0
        ? const []
        : controller.disputes.sublist(startIndex, endIndex);

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: AdminFilterBar(
                value: controller.filter,
                onChanged: (filter) {
                  setState(() => _page = 0);
                  context.read<AdminDisputesController>().setFilter(filter);
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<AdminDisputesController>().load(),
                child: controller.isLoading
                    ? const AdminQueueSkeleton()
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
                            title: open
                                ? 'No delivery problems waiting for review.'
                                : 'No closed delivery problems yet.',
                            message: open
                                ? 'Buyer delivery issues will appear here.'
                                : 'Closed cases will appear here.',
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          Text(
                            adminQueueStatusLine(
                              controller.disputes.length,
                              open ? 'open' : 'closed',
                            ),
                            style: AppTypography.subheading,
                          ),
                          const SizedBox(height: 4),
                          for (var i = 0; i < pageDisputes.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _DisputeRow(dispute: pageDisputes[i], open: open),
                          ],
                          const SizedBox(height: 16),
                          AdminPagination(
                            currentPage: safePage,
                            totalItems: total,
                            pageSize: _pageSize,
                            pageSizeOptions: const [10, 25, 50],
                            onPageChanged: (newPage) =>
                                setState(() => _page = newPage),
                            onPageSizeChanged: (newSize) => setState(() {
                              _pageSize = newSize;
                              _page = 0;
                            }),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisputeRow extends StatelessWidget {
  const _DisputeRow({required this.dispute, required this.open});

  final dynamic dispute;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final seller = adminHandle(
      dispute.sellerUsername,
      dispute.sellerDisplayName,
    );

    return AdminQueueItem(
      title: dispute.reason.label,
      status: dispute.status,
      statusLabel: disputeStatusLabel(dispute.status),
      lines: [
        if (dispute.orderNumber != null) 'Order #${dispute.orderNumber}',
        'Buyer ${adminHandle(dispute.buyerUsername, dispute.buyerDisplayName)}',
        if (seller != 'Member' && seller != 'Seller') 'Seller $seller',
      ],
      meta: formatCompactDate(dispute.createdAt),
      actionLabel: open ? 'Review case' : 'View case',
      onTap: () => _open(context, dispute.id),
    );
  }

  Future<void> _open(BuildContext context, String disputeId) async {
    await context.push(RouteNames.adminDisputeDetailFor(disputeId));
    if (context.mounted) {
      await context.read<AdminDisputesController>().load();
    }
  }
}
