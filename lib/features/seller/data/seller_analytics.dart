import '../../../core/utils/supabase_rpc.dart';
import 'seller_earnings.dart';

class SellerAnalyticsChartPoint {
  const SellerAnalyticsChartPoint({
    required this.bucketStart,
    required this.earningsCentavos,
  });

  final DateTime? bucketStart;
  final int earningsCentavos;

  factory SellerAnalyticsChartPoint.fromMap(Map<String, dynamic> map) {
    DateTime? parse(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return SellerAnalyticsChartPoint(
      bucketStart: parse(map['bucket_start']),
      earningsCentavos: readCentavos(map['earnings_centavos']),
    );
  }
}

class SellerAnalyticsRecentSale {
  const SellerAnalyticsRecentSale({
    required this.orderId,
    required this.orderNumber,
    required this.title,
    required this.sellerAmountCentavos,
    this.releasedAt,
  });

  final String orderId;
  final String orderNumber;
  final String title;
  final int sellerAmountCentavos;
  final DateTime? releasedAt;

  factory SellerAnalyticsRecentSale.fromMap(Map<String, dynamic> map) {
    DateTime? parse(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return SellerAnalyticsRecentSale(
      orderId: map['order_id']?.toString() ?? '',
      orderNumber: map['order_number']?.toString() ?? '',
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title'] as String
          : 'Order',
      sellerAmountCentavos: readCentavos(map['seller_amount_centavos']),
      releasedAt: parse(map['released_at']),
    );
  }
}

class SellerAnalyticsReport {
  const SellerAnalyticsReport({
    required this.earningsCentavos,
    required this.previousEarningsCentavos,
    required this.productsSold,
    required this.previousProductsSold,
    required this.completedOrders,
    required this.chart,
    required this.recentSales,
    required this.includeComparison,
  });

  final int earningsCentavos;
  final int previousEarningsCentavos;
  final int productsSold;
  final int previousProductsSold;
  final int completedOrders;
  final List<SellerAnalyticsChartPoint> chart;
  final List<SellerAnalyticsRecentSale> recentSales;
  final bool includeComparison;

  factory SellerAnalyticsReport.fromMap(
    Map<String, dynamic> map, {
    required bool includeComparison,
  }) {
    List<Map<String, dynamic>> asMaps(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return SellerAnalyticsReport(
      earningsCentavos: readCentavos(map['earnings_centavos']),
      previousEarningsCentavos: readCentavos(map['previous_earnings_centavos']),
      productsSold: readCentavos(map['products_sold']),
      previousProductsSold: readCentavos(map['previous_products_sold']),
      completedOrders: readCentavos(map['completed_orders']),
      chart: asMaps(
        map['chart'],
      ).map(SellerAnalyticsChartPoint.fromMap).toList(),
      recentSales: asMaps(
        map['recent_sales'],
      ).map(SellerAnalyticsRecentSale.fromMap).toList(),
      includeComparison: includeComparison,
    );
  }

  static SellerAnalyticsReport? tryParseRpc(
    Object? rpcRes, {
    required bool includeComparison,
  }) {
    if (!supabaseRpcSuccess(rpcRes)) return null;
    final map = supabaseRpcMap(rpcRes);
    if (map == null) return null;
    return SellerAnalyticsReport.fromMap(
      map,
      includeComparison: includeComparison,
    );
  }
}
