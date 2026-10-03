import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import 'seller_analytics.dart';
import 'seller_analytics_period.dart';

class SellerAnalyticsService {
  SellerAnalyticsService(this._supabase);

  final SupabaseService _supabase;

  Future<({SellerAnalyticsReport? report, String? error})> loadReport(
    SellerAnalyticsPeriodWindow window,
  ) async {
    const userFallback = 'Unable to load analytics. Please try again.';
    try {
      if (kDebugMode) {
        debugPrint('seller_analytics_report: request started');
      }
      final params = <String, dynamic>{
        'p_include_compare': window.includeCompare,
        'p_chart_bucket': window.chartBucket,
      };
      if (window.rangeStart != null) {
        params['p_range_start'] = window.rangeStart!.toUtc().toIso8601String();
      }
      if (window.rangeEnd != null) {
        params['p_range_end'] = window.rangeEnd!.toUtc().toIso8601String();
      }
      if (window.compareStart != null) {
        params['p_compare_start'] = window.compareStart!.toUtc().toIso8601String();
      }
      if (window.compareEnd != null) {
        params['p_compare_end'] = window.compareEnd!.toUtc().toIso8601String();
      }

      final rpcRes = await _supabase.client.rpc(
        'seller_analytics_report',
        params: params,
      );

      if (!supabaseRpcSuccess(rpcRes)) {
        if (kDebugMode) {
          debugPrint(
            'seller_analytics_report: RPC success=false ${supabaseRpcMap(rpcRes)}',
          );
        }
        return (
          report: null,
          error: supabaseRpcError(rpcRes, fallback: userFallback) ??
              userFallback,
        );
      }

      final report = SellerAnalyticsReport.tryParseRpc(
        rpcRes,
        includeComparison: window.includeCompare,
      );
      if (report == null) {
        if (kDebugMode) {
          debugPrint(
            'seller_analytics_report: response mapping failed '
            'type=${rpcRes.runtimeType}',
          );
        }
        return (report: null, error: userFallback);
      }
      if (kDebugMode) {
        debugPrint('seller_analytics_report: loaded successfully');
      }
      return (report: report, error: null);
    } on PostgrestException catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'seller_analytics_report PostgrestException: '
          '${e.code} ${e.message}\n$st',
        );
      }
      final missingFn = e.code == 'PGRST202' ||
          (e.message.contains('seller_analytics_report'));
      return (
        report: null,
        error: missingFn
            ? 'Analytics is not available yet. Apply the latest database update, then try again.'
            : userFallback,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('seller_analytics_report error: $e\n$st');
      }
      return (report: null, error: userFallback);
    }
  }
}
