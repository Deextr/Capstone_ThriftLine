import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';

class PurchaseHistoryScreen extends StatelessWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orders = context.watch<DataProvider>().ordersForBuyer(auth.user?.id ?? 'buyer_maya');

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase History'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: orders.isEmpty
            ? const Center(child: Text('No purchases yet'))
            : ListView.builder(
                itemCount: orders.length,
                itemBuilder: (_, i) {
                  final o = orders[i];
                  return ListTile(
                    title: Text(o.productTitle, style: AppTypography.body),
                    subtitle: Text('#${o.orderNumber} • ${o.status.name}'),
                    trailing: Text(formatCurrency(o.total), style: AppTypography.subheading.copyWith(color: const Color(0xFF0D9488), fontSize: 14)),
                    onTap: () => context.push('/track-order/${o.id}'),
                  );
                },
              ),
      ),
    );
  }
}
