import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class AdminTransactionRow {
  const AdminTransactionRow({
    required this.paymentId,
    required this.orderId,
    required this.orderNumber,
    required this.buyerName,
    required this.sellerName,
    required this.grossAmount,
    required this.platformFee,
    required this.sellerAmount,
    required this.paymentStatus,
    required this.createdAt,
    required this.paidAmount,
  });

  final String paymentId;
  final String orderId;
  final String orderNumber;
  final String buyerName;
  final String sellerName;
  final double grossAmount;
  final double platformFee;
  final double sellerAmount;
  final String paymentStatus;
  final DateTime createdAt;
  final double paidAmount;

  factory AdminTransactionRow.fromJson(Map<String, dynamic> json) {
    final order = json['orders'];
    final buyer = order is Map ? order['buyer'] : null;
    final seller = order is Map ? order['seller'] : null;
    final subtotal = order is Map
        ? (order['subtotal'] as num?)?.toDouble() ?? 0
        : 0;
    final shipping = order is Map
        ? (order['shipping_fee'] as num?)?.toDouble() ?? 0
        : 0;
    final platform = order is Map
        ? (order['platform_fee'] as num?)?.toDouble() ?? 0
        : 0;
    final amount = (json['amount_centavos'] as num?)?.toDouble() ?? 0;
    return AdminTransactionRow(
      paymentId: json['payment_id'] as String? ?? '',
      orderId: order is Map ? order['order_id'] as String? ?? '' : '',
      orderNumber: order is Map
          ? (order['order_number'] as String?)?.trim() ?? ''
          : '',
      buyerName: buyer is Map
          ? (buyer['full_name'] as String?)?.trim() ?? 'Buyer'
          : 'Buyer',
      sellerName: seller is Map
          ? (seller['full_name'] as String?)?.trim() ?? 'Seller'
          : 'Seller',
      grossAmount: (subtotal + shipping).toDouble(),
      platformFee: platform.toDouble(),
      sellerAmount: (subtotal + shipping - platform)
          .clamp(0, double.infinity)
          .toDouble(),
      paymentStatus: (json['payment_status'] as String?)?.trim() ?? 'pending',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      paidAmount: amount / 100,
    );
  }
}

class AdminTransactionsPage {
  const AdminTransactionsPage({required this.rows, required this.total});

  final List<AdminTransactionRow> rows;
  final int total;
}

class AdminTransactionsService {
  AdminTransactionsService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminTransactionsPage> list({
    required int page,
    required int pageSize,
    String? paymentStatus,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    var filter = _supabase.client
        .from('payments')
        .select(
          'payment_id, payment_status, amount_centavos, created_at, '
          'orders(order_id, order_number, subtotal, shipping_fee, platform_fee, '
          'buyer:buyer_id(full_name), seller:seller_id(full_name))',
        );

    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      filter = filter.eq('payment_status', paymentStatus);
    }

    final response = await filter
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    final rows = data
        .map(
          (row) => AdminTransactionRow.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
    return AdminTransactionsPage(rows: rows, total: response.count);
  }
}
