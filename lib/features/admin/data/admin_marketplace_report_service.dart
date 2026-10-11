import '../../../core/services/supabase_service.dart';
import '../domain/marketplace_report_catalog.dart';
import 'marketplace_report_models.dart';

class AdminMarketplaceReportService {
  AdminMarketplaceReportService(this._supabase);

  final SupabaseService _supabase;

  Future<MarketplaceReportPayload> loadReport({
    required MarketplaceReportCategory category,
    required MarketplaceReportDateWindow window,
    Map<String, String> filters = const {},
    int limit = marketplaceReportPageSize,
    int offset = 0,
    bool complete = false,
  }) async {
    final rpcCategory = complete ? 'all' : marketplaceReportCategoryRpcValue(category);
    final raw = await _supabase.client.rpc(
      'admin_marketplace_report',
      params: {
        'p_category': rpcCategory,
        'p_from': window.from.toUtc().toIso8601String(),
        'p_to': window.toExclusive.toUtc().toIso8601String(),
        'p_compare_from': null,
        'p_compare_to': null,
        'p_filters': filters,
        'p_detail_limit': limit,
        'p_detail_offset': offset,
      },
    );

    if (raw is! Map) {
      return MarketplaceReportPayload(
        success: false,
        category: rpcCategory,
        generatedAt: null,
        rangeFrom: window.from,
        rangeTo: window.toExclusive,
        summary: const [],
        comparison: const [],
        breakdowns: const [],
        details: MarketplaceReportDetails.empty,
        detailTotal: 0,
        limitations: const [],
        error: 'Unexpected response from server.',
      );
    }

    final map = Map<String, dynamic>.from(raw);
    return MarketplaceReportPayload.fromJson(map);
  }
}

bool isMarketplaceReportOfflineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('host lookup') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('offline') ||
      text.contains('timed out');
}

String marketplaceReportErrorMessage(Object error) {
  if (isMarketplaceReportOfflineError(error)) {
    return 'You appear to be offline. Connect and try again.';
  }
  final text = error.toString();
  if (text.contains('42501') || text.toLowerCase().contains('admin')) {
    return 'You do not have permission to view this report.';
  }
  if (text.contains('PGRST202') || text.contains('admin_marketplace_report')) {
    return 'Reporting service is not available. Apply the latest database migrations.';
  }
  if (text.contains('is not a subtype') || text.contains('type cast')) {
    return 'Report data could not be read. Please retry.';
  }
  final message = _postgrestMessage(error);
  if (message != null && message.isNotEmpty) return message;
  return 'Unable to load marketplace report.';
}

String? _postgrestMessage(Object error) {
  final text = error.toString();
  final match = RegExp(r'message:\s*([^,}\n]+)').firstMatch(text);
  final message = match?.group(1)?.trim();
  if (message == null || message.isEmpty) return null;
  if (message.length > 180) return '${message.substring(0, 177)}...';
  return message;
}
