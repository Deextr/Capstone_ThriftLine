import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../buyer/data/order_query.dart';
import '../../../models/order_model.dart';
import '../domain/admin_order_management.dart';
import 'delivery_payment_hold.dart';

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
    required this.orderKind,
    required this.unifiedStatus,
  });

  final String orderId;
  final String orderNumber;
  final String buyerName;
  final String sellerName;
  final double totalAmount;
  final String paymentStatus;
  final String orderStatus;
  final DateTime createdAt;
  final AdminOrderKind orderKind;
  final AdminUnifiedOrderStatus unifiedStatus;

  factory AdminOrderRow.fromJson(Map<String, dynamic> json) {
    final buyer = json['buyer'];
    final seller = json['seller'];
    final paymentStatus = _paymentFromRow(json);
    final orderStatus = (json['order_status'] as String?)?.trim() ?? 'pending';
    final escrowStatus = _escrowStatusFromRow(json);
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
      paymentStatus: paymentStatus,
      orderStatus: orderStatus,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      orderKind: adminOrderKindFromRow(
        orderType: json['order_type'] as String?,
        auctionId: json['auction_id'] as String?,
      ),
      unifiedStatus: adminUnifiedOrderStatus(
        orderStatusDb: orderStatus,
        paymentStatus: paymentStatus,
        escrowStatus: escrowStatus,
      ),
    );
  }

  String get statusLabel => unifiedStatus.label;
}

String? _escrowStatusFromRow(Map<String, dynamic> json) {
  final raw = json['escrow'];
  if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    if (first is Map) {
      return (first['status'] as String?)?.trim();
    }
  }
  if (raw is Map) {
    return (raw['status'] as String?)?.trim();
  }
  return null;
}

String _paymentFromRow(Map<String, dynamic> json) {
  final payments = json['payments'];
  if (payments is! List || payments.isEmpty) return 'pending';

  Map<String, dynamic>? paid;
  Map<String, dynamic>? latest;
  for (final raw in payments) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    latest = map;
    final status = (map['payment_status'] as String?)?.trim().toLowerCase();
    if (status == 'paid') {
      paid = map;
      break;
    }
  }
  final chosen = paid ?? latest;
  if (chosen == null) return 'pending';
  return (chosen['payment_status'] as String?)?.trim() ?? 'pending';
}

class AdminOrdersPage {
  const AdminOrdersPage({required this.rows, required this.total});

  final List<AdminOrderRow> rows;
  final int total;
}

class AdminCheckoutSiblingSummary {
  const AdminCheckoutSiblingSummary({
    required this.orderId,
    required this.orderNumber,
    required this.totalAmount,
    required this.sellerName,
  });

  final String orderId;
  final String orderNumber;
  final double totalAmount;
  final String sellerName;
}

class AdminOrderReportSummary {
  const AdminOrderReportSummary({
    required this.reportId,
    required this.status,
    required this.reason,
    required this.createdAt,
  });

  final String reportId;
  final String status;
  final String reason;
  final DateTime createdAt;
}

class AdminOrderDetailBundle {
  const AdminOrderDetailBundle({
    required this.order,
    required this.payments,
    this.escrow,
    this.escrowRow,
    this.siblings = const [],
    this.reports = const [],
    this.sellerShopName,
    this.buyerUsername,
    this.sellerUsername,
    this.loadWarnings = const [],
    required this.orderKind,
  });

  final OrderModel order;
  final AdminOrderKind orderKind;
  final List<Map<String, dynamic>> payments;
  final DeliveryPaymentHold? escrow;
  final Map<String, dynamic>? escrowRow;
  final List<AdminCheckoutSiblingSummary> siblings;
  final List<AdminOrderReportSummary> reports;
  final String? sellerShopName;
  final String? buyerUsername;
  final String? sellerUsername;
  final List<String> loadWarnings;

  AdminUnifiedOrderStatus get unifiedStatus =>
      adminUnifiedOrderStatusFromOrder(order, escrow: escrow);

  double get itemsSubtotal => order.amount;

  double get sellerAllocation =>
      (order.amount + order.shippingFee - order.platformFee).clamp(
        0,
        double.infinity,
      );

  Map<String, dynamic>? get primaryPayment {
    if (payments.isEmpty) return null;
    for (final p in payments) {
      if ((p['payment_status'] as String?)?.trim().toLowerCase() == 'paid') {
        return p;
      }
    }
    return payments.first;
  }
}

class AdminOrdersService {
  AdminOrdersService(this._supabase);

  final SupabaseService _supabase;

  static const _listSelectBase =
      'order_id, order_number, order_type, auction_id, total_amount, '
      'order_status, created_at, '
      'buyer:buyer_id(full_name), seller:seller_id(full_name), '
      'payments(payment_status, created_at), escrow(status)';

  static const _listSelectPaymentInner =
      'order_id, order_number, order_type, auction_id, total_amount, '
      'order_status, created_at, '
      'buyer:buyer_id(full_name), seller:seller_id(full_name), '
      'payments!inner(payment_status, created_at), escrow(status)';

  Future<AdminOrdersPage> list({
    required int page,
    required int pageSize,
    AdminOrderCategory category = AdminOrderCategory.all,
    AdminUnifiedStatusFilter unifiedStatus = AdminUnifiedStatusFilter.any,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    AdminOrdersSort sort = AdminOrdersSort.newest,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    final needsPaymentInner = _needsPaymentInnerJoin(unifiedStatus);

    var filter = _supabase.client
        .from('orders')
        .select(needsPaymentInner ? _listSelectPaymentInner : _listSelectBase);

    final orderType = category.dbOrderType;
    if (orderType != null) {
      filter = filter.eq('order_type', orderType);
    }

    filter =
        _applyUnifiedStatusFilter(filter, unifiedStatus)
            as PostgrestFilterBuilder<PostgrestList>;

    final term = search.trim();
    if (term.isNotEmpty) {
      if (looksLikeUuid(term)) {
        filter = filter.eq('order_id', term);
      } else {
        final escaped = term.replaceAll(',', '').replaceAll('%', '');
        final pattern = '%$escaped%';
        filter = filter.or(
          'order_number.ilike.$pattern,buyer.full_name.ilike.$pattern,'
          'seller.full_name.ilike.$pattern',
        );
      }
    }

    if (dateFrom != null) {
      filter = filter.gte(
        'created_at',
        _startOfDay(dateFrom).toIso8601String(),
      );
    }
    if (dateTo != null) {
      filter = filter.lte('created_at', _endOfDay(dateTo).toIso8601String());
    }

    final (column, ascending) = switch (sort) {
      AdminOrdersSort.newest => ('created_at', false),
      AdminOrdersSort.oldest => ('created_at', true),
      AdminOrdersSort.amountHigh => ('total_amount', false),
      AdminOrdersSort.amountLow => ('total_amount', true),
    };

    try {
      final response = await filter
          .order(column, ascending: ascending)
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
    } on PostgrestException catch (e) {
      debugPrint('AdminOrdersService.list escrow embed failed: $e');
      return _listWithoutEscrowEmbed(
        page: page,
        pageSize: pageSize,
        category: category,
        unifiedStatus: unifiedStatus,
        search: search,
        dateFrom: dateFrom,
        dateTo: dateTo,
        sort: sort,
        from: from,
        to: to,
        column: column,
        ascending: ascending,
        needsPaymentInner: needsPaymentInner,
      );
    }
  }

  Future<AdminOrdersPage> _listWithoutEscrowEmbed({
    required int page,
    required int pageSize,
    required AdminOrderCategory category,
    required AdminUnifiedStatusFilter unifiedStatus,
    required String search,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required AdminOrdersSort sort,
    required int from,
    required int to,
    required String column,
    required bool ascending,
    required bool needsPaymentInner,
  }) async {
    const selectNoEscrow =
        'order_id, order_number, order_type, auction_id, total_amount, '
        'order_status, created_at, '
        'buyer:buyer_id(full_name), seller:seller_id(full_name), '
        'payments(payment_status, created_at)';
    const selectNoEscrowPaymentInner =
        'order_id, order_number, order_type, auction_id, total_amount, '
        'order_status, created_at, '
        'buyer:buyer_id(full_name), seller:seller_id(full_name), '
        'payments!inner(payment_status, created_at)';

    var filter = _supabase.client
        .from('orders')
        .select(
          needsPaymentInner ? selectNoEscrowPaymentInner : selectNoEscrow,
        );

    final orderType = category.dbOrderType;
    if (orderType != null) {
      filter = filter.eq('order_type', orderType);
    }
    filter =
        _applyUnifiedStatusFilter(filter, unifiedStatus)
            as PostgrestFilterBuilder<PostgrestList>;

    final term = search.trim();
    if (term.isNotEmpty) {
      if (looksLikeUuid(term)) {
        filter = filter.eq('order_id', term);
      } else {
        final escaped = term.replaceAll(',', '').replaceAll('%', '');
        final pattern = '%$escaped%';
        filter = filter.or(
          'order_number.ilike.$pattern,buyer.full_name.ilike.$pattern,'
          'seller.full_name.ilike.$pattern',
        );
      }
    }

    if (dateFrom != null) {
      filter = filter.gte(
        'created_at',
        _startOfDay(dateFrom).toIso8601String(),
      );
    }
    if (dateTo != null) {
      filter = filter.lte('created_at', _endOfDay(dateTo).toIso8601String());
    }

    final response = await filter
        .order(column, ascending: ascending)
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

  bool _needsPaymentInnerJoin(AdminUnifiedStatusFilter filter) {
    return switch (filter) {
      AdminUnifiedStatusFilter.refunded ||
      AdminUnifiedStatusFilter.paymentFailed ||
      AdminUnifiedStatusFilter.cancelledPaidReview ||
      AdminUnifiedStatusFilter.awaitingPayment => true,
      _ => false,
    };
  }

  PostgrestFilterBuilder<dynamic> _applyUnifiedStatusFilter(
    PostgrestFilterBuilder<dynamic> filter,
    AdminUnifiedStatusFilter unifiedStatus,
  ) {
    return switch (unifiedStatus) {
      AdminUnifiedStatusFilter.any => filter,
      AdminUnifiedStatusFilter.awaitingPayment =>
        filter
            .eq('order_status', 'pending')
            .eq('payments.payment_status', 'pending'),
      AdminUnifiedStatusFilter.preparing => filter.eq('order_status', 'paid'),
      AdminUnifiedStatusFilter.shipped => filter.eq('order_status', 'shipped'),
      AdminUnifiedStatusFilter.completed => filter.eq(
        'order_status',
        'completed',
      ),
      AdminUnifiedStatusFilter.cancelled => filter.eq(
        'order_status',
        'cancelled',
      ),
      AdminUnifiedStatusFilter.cancelledPaidReview =>
        filter
            .eq('order_status', 'cancelled')
            .eq('payments.payment_status', 'paid'),
      AdminUnifiedStatusFilter.refunded => filter.eq(
        'payments.payment_status',
        'refunded',
      ),
      AdminUnifiedStatusFilter.paymentFailed => filter.or(
        'payments.payment_status.eq.failed,payments.payment_status.eq.expired',
      ),
    };
  }

  Future<AdminOrderDetailBundle?> fetchOrderDetailBundle(String orderId) async {
    final warnings = <String>[];
    Map<String, dynamic>? map;

    try {
      final row = await runAdminOrderDetailSelect(
        (select) => _supabase.client
            .from('orders')
            .select(select)
            .eq('order_id', orderId)
            .maybeSingle(),
      );
      if (row == null) return null;
      map = Map<String, dynamic>.from(row as Map);
    } catch (e, st) {
      debugPrint('AdminOrdersService.fetchOrderDetailBundle primary: $e\n$st');
      try {
        final row = await _supabase.client
            .from('orders')
            .select('*, items:order_items(*), payments(*)')
            .eq('order_id', orderId)
            .maybeSingle();
        if (row == null) return null;
        map = Map<String, dynamic>.from(row);
        warnings.add('Loaded without shipment details.');
      } catch (e2) {
        debugPrint('AdminOrdersService.fetchOrderDetailBundle fallback: $e2');
        rethrow;
      }
    }

    Map<String, Map<String, dynamic>> profiles = {};
    try {
      profiles = await loadPublicProfiles(_supabase, [
        map['buyer_id'] as String? ?? '',
        map['seller_id'] as String? ?? '',
      ]);
    } catch (e) {
      debugPrint('loadPublicProfiles failed: $e');
      warnings.add('Buyer or seller profile could not be loaded.');
    }

    OrderModel order;
    try {
      order = OrderModel.fromSupabase(
        map,
        buyer: profiles[map['buyer_id'] as String?],
        seller: profiles[map['seller_id'] as String?],
      );
    } catch (e) {
      debugPrint('OrderModel.fromSupabase failed: $e');
      return null;
    }

    final payments = _normalizePayments(map['payments']);

    DeliveryPaymentHold? escrow;
    Map<String, dynamic>? escrowRow;
    try {
      escrowRow = await _loadEscrowRow(orderId);
      if (escrowRow != null) {
        escrow = DeliveryPaymentHold.fromSupabase(escrowRow);
      }
    } catch (e) {
      debugPrint('escrow load failed: $e');
      warnings.add('Escrow record unavailable.');
    }

    final buyerProfile = profiles[map['buyer_id'] as String?];
    final sellerProfile = profiles[map['seller_id'] as String?];

    var siblings = const <AdminCheckoutSiblingSummary>[];
    final groupId = map['checkout_group_id'] as String?;
    if (groupId != null && groupId.isNotEmpty) {
      siblings = await _loadCheckoutSiblings(groupId, order.id);
    }

    final reports = await _loadOrderReports(order.id);

    final kind = adminOrderKindFromRow(
      orderType: map['order_type'] as String?,
      auctionId: map['auction_id'] as String?,
    );

    return AdminOrderDetailBundle(
      order: order,
      orderKind: kind,
      payments: payments,
      escrow: escrow,
      escrowRow: escrowRow,
      siblings: siblings,
      reports: reports,
      sellerShopName: sellerProfile?['shop_name'] as String?,
      buyerUsername: buyerProfile?['username'] as String?,
      sellerUsername: sellerProfile?['username'] as String?,
      loadWarnings: warnings,
    );
  }

  Future<Map<String, dynamic>?> _loadEscrowRow(String orderId) async {
    final row = await _supabase.client
        .from('escrow')
        .select('*')
        .eq('order_id', orderId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
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

  List<Map<String, dynamic>> _normalizePayments(dynamic raw) {
    if (raw is! List) return const [];
    final list = [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    list.sort((a, b) {
      final aT =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bT =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aT.compareTo(bT);
    });
    return list;
  }

  Future<List<AdminCheckoutSiblingSummary>> _loadCheckoutSiblings(
    String checkoutGroupId,
    String currentOrderId,
  ) async {
    try {
      final rows = await _supabase.client
          .from('orders')
          .select(
            'order_id, order_number, total_amount, '
            'seller:seller_id(full_name)',
          )
          .eq('checkout_group_id', checkoutGroupId)
          .order('created_at', ascending: true);
      final out = <AdminCheckoutSiblingSummary>[];
      for (final raw in rows as List<dynamic>) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = map['order_id'] as String? ?? '';
        if (id == currentOrderId) continue;
        final seller = map['seller'];
        out.add(
          AdminCheckoutSiblingSummary(
            orderId: id,
            orderNumber: (map['order_number'] as String?)?.trim() ?? '',
            totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
            sellerName: seller is Map
                ? (seller['full_name'] as String?)?.trim() ?? 'Seller'
                : 'Seller',
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<AdminOrderReportSummary>> _loadOrderReports(
    String orderId,
  ) async {
    try {
      final rows = await _supabase.client
          .from('reports')
          .select('report_id, status, reason, created_at')
          .eq('order_id', orderId)
          .order('created_at', ascending: false);
      return [
        for (final raw in rows as List<dynamic>)
          if (raw is Map)
            AdminOrderReportSummary(
              reportId: raw['report_id']?.toString() ?? '',
              status: (raw['status'] as String?)?.trim() ?? '',
              reason: (raw['reason'] as String?)?.trim() ?? '',
              createdAt:
                  DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
