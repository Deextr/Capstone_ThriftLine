import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../buyer/data/order_query.dart';
import 'admin_portal_data_access.dart';

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

  factory AdminTransactionRow.fromJson(
    Map<String, dynamic> json, {
    Map<String, Map<String, dynamic>>? profiles,
  }) {
    final order = json['orders'];
    final buyerId = order is Map ? order['buyer_id'] as String? : null;
    final sellerId = order is Map ? order['seller_id'] as String? : null;
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

    String nameFromProfile(String? id, Map? embedded, String fallback) {
      if (embedded is Map) {
        final fromEmbed = (embedded['full_name'] as String?)?.trim();
        if (fromEmbed != null && fromEmbed.isNotEmpty) return fromEmbed;
      }
      if (id != null && profiles != null) {
        final profile = profiles[id];
        final fromProfile = (profile?['full_name'] as String?)?.trim();
        if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
      }
      return fallback;
    }

    return AdminTransactionRow(
      paymentId: json['payment_id'] as String? ?? '',
      orderId: order is Map ? order['order_id'] as String? ?? '' : '',
      orderNumber: order is Map
          ? (order['order_number'] as String?)?.trim() ?? ''
          : '',
      buyerName: nameFromProfile(buyerId, buyer is Map ? buyer : null, 'Buyer'),
      sellerName: nameFromProfile(
        sellerId,
        seller is Map ? seller : null,
        'Seller',
      ),
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

  static const _selectWithProfiles =
      'payment_id, payment_status, amount_centavos, created_at, '
      'orders(order_id, order_number, subtotal, shipping_fee, platform_fee, '
      'buyer_id, seller_id, '
      'buyer:buyer_id(full_name), seller:seller_id(full_name))';

  static const _selectOrderIdsOnly =
      'payment_id, payment_status, amount_centavos, created_at, '
      'orders(order_id, order_number, subtotal, shipping_fee, platform_fee, '
      'buyer_id, seller_id)';

  Future<AdminTransactionsPage> list({
    required int page,
    required int pageSize,
    String? paymentStatus,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    try {
      return await _listWithSelect(
        select: _selectWithProfiles,
        from: from,
        to: to,
        paymentStatus: paymentStatus,
      );
    } on PostgrestException catch (e) {
      debugPrint('AdminTransactionsService.list embed failed: $e');
      if (!_postgrestEmbedRecoverable(e)) rethrow;
      return _listWithSelect(
        select: _selectOrderIdsOnly,
        from: from,
        to: to,
        paymentStatus: paymentStatus,
        hydrateProfiles: true,
      );
    }
  }

  static bool _postgrestEmbedRecoverable(PostgrestException error) {
    final code = error.code?.trim() ?? '';
    if (code == 'PGRST200' || code == 'PGRST201') return true;
    final message = error.message.toLowerCase();
    return message.contains('relationship') ||
        message.contains('users') ||
        message.contains('could not embed') ||
        message.contains('schema cache');
  }

  Future<AdminTransactionsPage> _listWithSelect({
    required String select,
    required int from,
    required int to,
    required String? paymentStatus,
    bool hydrateProfiles = false,
  }) async {
    var filter = (await resolveAdminClient(_supabase))
        .from('payments')
        .select(select);

    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      filter = filter.eq('payment_status', paymentStatus);
    }

    final response = await filter
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    Map<String, Map<String, dynamic>> profiles = {};
    if (hydrateProfiles && data.isNotEmpty) {
      final ids = <String>{};
      for (final raw in data) {
        if (raw is! Map) continue;
        final order = raw['orders'];
        if (order is Map) {
          final buyerId = order['buyer_id'] as String?;
          final sellerId = order['seller_id'] as String?;
          if (buyerId != null && buyerId.isNotEmpty) ids.add(buyerId);
          if (sellerId != null && sellerId.isNotEmpty) ids.add(sellerId);
        }
      }
      profiles = await loadPublicProfiles(_supabase, ids);
    }

    final rows = data
        .map(
          (row) => AdminTransactionRow.fromJson(
            Map<String, dynamic>.from(row as Map),
            profiles: hydrateProfiles ? profiles : null,
          ),
        )
        .toList();
    return AdminTransactionsPage(rows: rows, total: response.count);
  }
}
