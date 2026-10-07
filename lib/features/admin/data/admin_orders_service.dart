import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';

class AdminOrderRow {
  const AdminOrderRow({
    required this.orderId,
    required this.orderNumber,
    required this.buyerName,
    required this.sellerName,
    required this.totalAmount,
    required this.paymentStatus,
    required this.orderStatus,
    required this.createdAt,
  });

  final String orderId;
  final String orderNumber;
  final String buyerName;
  final String sellerName;
  final double totalAmount;
  final String paymentStatus;
  final String orderStatus;
  final DateTime createdAt;

  factory AdminOrderRow.fromJson(Map<String, dynamic> json) {
    final buyer = json['buyer'];
    final seller = json['seller'];
    return AdminOrderRow(
      orderId: json['order_id'] as String,
      orderNumber: (json['order_number'] as String?)?.trim() ?? '',
      buyerName: buyer is Map
          ? (buyer['full_name'] as String?)?.trim() ?? 'Buyer'
          : 'Buyer',
      sellerName: seller is Map
          ? (seller['full_name'] as String?)?.trim() ?? 'Seller'
          : 'Seller',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paymentStatus: _paymentFromRow(json),
      orderStatus: (json['order_status'] as String?)?.trim() ?? 'pending',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String get statusLabel => orderStatusLabel(orderStatusFromDb(orderStatus));
}

String _paymentFromRow(Map<String, dynamic> json) {
  final payments = json['payments'];
  if (payments is List && payments.isNotEmpty) {
    final first = payments.first;
    if (first is Map) {
      return (first['payment_status'] as String?)?.trim() ?? 'pending';
    }
  }
  return 'pending';
}

class AdminOrdersPage {
  const AdminOrdersPage({required this.rows, required this.total});

  final List<AdminOrderRow> rows;
  final int total;
}

class AdminOrdersService {
  AdminOrdersService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminOrdersPage> list({
    required int page,
    required int pageSize,
    String? statusFilter,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    var filter = _supabase.client
        .from('orders')
        .select(
          'order_id, order_number, total_amount, order_status, created_at, '
          'buyer:buyer_id(full_name), seller:seller_id(full_name), '
          'payments(payment_status)',
        );

    if (statusFilter != null && statusFilter.isNotEmpty) {
      filter = filter.eq('order_status', statusFilter);
    }

    final response = await filter
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    final rows = data
        .map(
          (row) =>
              AdminOrderRow.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    return AdminOrdersPage(rows: rows, total: response.count);
  }

  Future<Map<String, dynamic>?> fetchOrderDetail(String orderId) async {
    return _supabase.client
        .from('orders')
        .select(
          '*, buyer:buyer_id(full_name, email), seller:seller_id(full_name, email), '
          'payments(*), order_items(*)',
        )
        .eq('order_id', orderId)
        .maybeSingle();
  }
}
