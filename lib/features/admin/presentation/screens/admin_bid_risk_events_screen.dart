import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_bid_risk_controller.dart';

class AdminBidRiskEventsScreen extends StatefulWidget {
  const AdminBidRiskEventsScreen({super.key});

  @override
  State<AdminBidRiskEventsScreen> createState() =>
      _AdminBidRiskEventsScreenState();
}

class _AdminBidRiskEventsScreenState extends State<AdminBidRiskEventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminBidRiskController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminBidRiskController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bid risk events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading ? null : controller.load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: _body(controller),
      ),
    );
  }

  Widget _body(AdminBidRiskController controller) {
    if (controller.isLoading && controller.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              controller.error!,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    if (controller.events.isEmpty) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No bid risk events recorded yet.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: controller.events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = controller.events[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.actionTaken.toUpperCase()} · ${event.riskLevel}',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Amount: ${formatCurrency(event.attemptedAmount)}',
                  style: AppTypography.body,
                ),
                if (event.reasons.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reasons: ${event.reasons.join(', ')}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: 4),
                Text(
                  event.createdAt.toLocal().toString(),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
