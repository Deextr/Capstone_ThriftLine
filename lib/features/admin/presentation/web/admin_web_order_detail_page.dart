import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/admin_orders_service.dart';
import 'package:provider/provider.dart';

class AdminWebOrderDetailPage extends StatefulWidget {
  const AdminWebOrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminWebOrderDetailPage> createState() =>
      _AdminWebOrderDetailPageState();
}

class _AdminWebOrderDetailPageState extends State<AdminWebOrderDetailPage> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = AdminOrdersService(context.read<SupabaseService>());
      _order = await service.fetchOrderDetail(widget.orderId);
    } catch (_) {
      _error = 'Unable to load this order.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to orders'),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: AppTypography.body)
          else if (_order != null) ...[
            Text(
              (_order!['order_number'] as String?) ?? 'Order',
              style: AppTypography.subheading.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text('Status: ${_order!['order_status']}'),
            Text('Total: ${_order!['total_amount']}'),
            Text('Payment: ${_order!['payments']}'),
          ],
        ],
      ),
    );
  }
}
