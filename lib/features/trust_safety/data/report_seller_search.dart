import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

const int kReportSellerSearchMinChars = 2;
const int kReportSellerSearchDebounceMs = 350;
const int kReportFollowingShopsPreviewLimit = 8;

class ReportSellerCandidate {
  const ReportSellerCandidate({
    required this.sellerId,
    required this.username,
    required this.displayName,
    required this.shopName,
    required this.avatarUrl,
  });

  final String sellerId;
  final String username;
  final String displayName;
  final String shopName;
  final String avatarUrl;

  String get primaryLabel =>
      shopName.trim().isNotEmpty ? shopName.trim() : displayName;

  String? get secondaryLabel {
    if (username.isEmpty) return null;
    return '@$username';
  }

  factory ReportSellerCandidate.fromSupabase(Map<String, dynamic> row) {
    final username = (row['username'] as String? ?? '').trim();
    final displayName =
        (row['full_name'] as String? ?? '').trim().isNotEmpty
            ? (row['full_name'] as String).trim()
            : username;
    final shopRaw = (row['shop_name'] as String? ?? '').trim();
    final shopName = shopRaw.isNotEmpty ? shopRaw : displayName;
    final avatar = (row['avatar'] as String? ?? '').trim();
    return ReportSellerCandidate(
      sellerId: row['seller_id'] as String? ?? '',
      username: username,
      displayName: displayName,
      shopName: shopName,
      avatarUrl: avatar,
    );
  }

  factory ReportSellerCandidate.fromFollowedShop({
    required String sellerId,
    required String username,
    required String shopName,
    required String ownerName,
    required String avatarUrl,
  }) {
    return ReportSellerCandidate(
      sellerId: sellerId,
      username: username,
      displayName: ownerName,
      shopName: shopName,
      avatarUrl: avatarUrl,
    );
  }
}

Future<List<ReportSellerCandidate>> searchReportableSellers(
  SupabaseService supabase,
  String query, {
  int limit = 15,
}) async {
  final rpcRes = await supabase.client.rpc(
    'search_reportable_sellers',
    params: {'p_query': query, 'p_limit': limit},
  );
  if (!supabaseRpcSuccess(rpcRes)) {
    throw Exception(
      supabaseRpcError(rpcRes, fallback: 'Unable to search sellers.'),
    );
  }
  final map = supabaseRpcMap(rpcRes);
  final items = map?['items'];
  if (items is! List) return const [];
  return items
      .whereType<Map>()
      .map((e) => ReportSellerCandidate.fromSupabase(Map<String, dynamic>.from(e)))
      .where((c) => c.sellerId.isNotEmpty)
      .toList();
}
