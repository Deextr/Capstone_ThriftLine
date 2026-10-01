import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchAnalyticsService {
  SearchAnalyticsService(this._client);

  final SupabaseClient _client;

  Future<void> recordSubmittedSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    try {
      await _client.rpc('record_product_search', params: {'p_term': trimmed});
    } catch (e) {
      debugPrint('SearchAnalyticsService.recordSubmittedSearch: $e');
    }
  }

  Future<List<String>> fetchPopularSearches({
    int limit = 8,
    int days = 14,
  }) async {
    try {
      final rows = await _client.rpc(
        'get_popular_product_searches',
        params: {'p_limit': limit, 'p_days': days, 'p_min_total_hits': 3},
      );
      if (rows is! List) return const [];
      return rows
          .map((row) {
            if (row is! Map) return null;
            final term = row['term'] as String?;
            if (term == null || term.trim().isEmpty) return null;
            return _titleCaseTerm(term.trim());
          })
          .whereType<String>()
          .toList();
    } catch (e) {
      debugPrint('SearchAnalyticsService.fetchPopularSearches: $e');
      return const [];
    }
  }
}

String _titleCaseTerm(String normalized) {
  if (normalized.isEmpty) return normalized;
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
