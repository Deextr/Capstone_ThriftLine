import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';

/// Nested select used by catalog screens.
///
/// Intentionally omits `user_public_profiles`. PostgREST cannot embed that
/// view from `products`, and `users` RLS hides other people's rows. Seller
/// display data is attached in [hydrateCatalogProducts].
const String productCatalogSelectWithoutAuctions =
    '*,images:product_images(image_url,is_primary,display_order),category:categories(category_name)';

const String productCatalogSelect =
    '$productCatalogSelectWithoutAuctions,auctions(auction_id,starting_price,minimum_increment,current_price,starts_at,ends_at,status)';

/// Strips PostgREST `or()` metacharacters so a typed query cannot break the
/// filter expression.
String sanitizeCatalogSearchQuery(String raw) {
  return raw
      .replaceAll(RegExp(r'[%_(),]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String catalogIlikeOrFilter(String sanitizedQuery) {
  final q = sanitizedQuery;
  return 'name.ilike.%$q%,description.ilike.%$q%,brand.ilike.%$q%';
}

bool isUniqueViolation(Object error) {
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    return code == '23505' ||
        message.contains('duplicate') ||
        message.contains('unique');
  }
  final text = error.toString().toLowerCase();
  return text.contains('23505') ||
      text.contains('duplicate') ||
      text.contains('unique');
}

/// Runs a products select that embeds auctions, then retries without auctions
/// when that table (Phase 3) has not been applied yet.
Future<T> runProductCatalogSelect<T>(
  Future<T> Function(String select) run,
) async {
  try {
    return await run(productCatalogSelect);
  } catch (e) {
    debugPrint('catalog select with auctions failed ($e); retrying without');
    return await run(productCatalogSelectWithoutAuctions);
  }
}

/// Approved shops, plus any extra seller ids (e.g. from a product page).
///
/// Public profile rows are loaded only for those ids — never the whole view.
Future<Map<String, Map<String, dynamic>>> fetchSellerProfilesMap(
  SupabaseClient client, {
  Iterable<String> extraSellerIds = const [],
  bool includeApproved = true,
}) async {
  final map = <String, Map<String, dynamic>>{};
  if (includeApproved) {
    try {
      final spResponse = await client
          .from('seller_profiles')
          .select()
          .eq('is_approved', true);
      map.addAll(sellerProfilesById(spResponse as List<dynamic>));
    } catch (e) {
      debugPrint('fetchSellerProfilesMap: seller_profiles error ($e)');
    }
  }

  final missing = extraSellerIds
      .where((id) => id.isNotEmpty && !map.containsKey(id))
      .toSet()
      .toList();
  if (missing.isNotEmpty) {
    try {
      final extra = await client
          .from('seller_profiles')
          .select()
          .inFilter('seller_id', missing);
      map.addAll(sellerProfilesById(extra as List<dynamic>));
    } catch (e) {
      debugPrint('fetchSellerProfilesMap: extra seller_profiles error ($e)');
    }
  }

  await attachPublicProfiles(client, map);

  final stillMissing = extraSellerIds
      .where((id) => id.isNotEmpty && !map.containsKey(id))
      .toSet()
      .toList();
  if (stillMissing.isNotEmpty) {
    try {
      final profiles = await client
          .from('user_public_profiles')
          .select()
          .inFilter('user_id', stillMissing);
      for (final u in profiles as List<dynamic>) {
        if (u is! Map<String, dynamic>) continue;
        final uid = u['user_id'] as String?;
        if (uid == null) continue;
        map[uid] = {
          'seller_id': uid,
          'shop_name': (u['full_name'] as String?)?.trim().isNotEmpty == true
              ? u['full_name']
              : (u['username'] ?? 'Seller'),
          'is_approved': u['role'] == 'seller',
          'user': u,
        };
      }
    } catch (e) {
      debugPrint('fetchSellerProfilesMap: missing public profiles error ($e)');
    }
  }

  return map;
}

Future<Map<String, dynamic>?> fetchHydratedSellerProfile(
  SupabaseClient client,
  String sellerId,
) async {
  final map = await fetchSellerProfilesMap(
    client,
    extraSellerIds: [sellerId],
    includeApproved: false,
  );
  return map[sellerId];
}

Future<void> attachPublicProfiles(
  SupabaseClient client,
  Map<String, Map<String, dynamic>> map,
) async {
  final ids = map.keys.toList();
  if (ids.isEmpty) return;
  try {
    final profiles = await client
        .from('user_public_profiles')
        .select()
        .inFilter('user_id', ids);
    for (final u in profiles as List<dynamic>) {
      if (u is! Map<String, dynamic>) continue;
      final uid = u['user_id'] as String?;
      if (uid == null) continue;
      if (map.containsKey(uid)) {
        map[uid] = {...map[uid]!, 'user': u};
      } else {
        map[uid] = {
          'seller_id': uid,
          'shop_name': (u['full_name'] as String?)?.trim().isNotEmpty == true
              ? u['full_name']
              : (u['username'] ?? 'Seller'),
          'is_approved': u['role'] == 'seller',
          'user': u,
        };
      }
    }
  } catch (e) {
    debugPrint('attachPublicProfiles error ($e)');
  }
}

Map<String, Map<String, dynamic>> sellerProfilesById(List<dynamic> rows) {
  final map = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    if (row is! Map<String, dynamic>) continue;
    final id = row['seller_id'] as String?;
    if (id != null) map[id] = row;
  }
  return map;
}

List<ProductModel> hydrateCatalogProducts(
  List<dynamic> rows,
  Map<String, Map<String, dynamic>> sellerProfiles,
) {
  return rows.map((row) {
    final r = row as Map<String, dynamic>;
    final sellerId = r['seller_id'] as String?;
    return ProductModel.fromSupabase(
      r,
      sellerProfile: sellerId != null ? sellerProfiles[sellerId] : null,
    );
  }).toList();
}

List<SellerProfile> verifiedSellersFromProfiles(
  Map<String, Map<String, dynamic>> sellerProfiles,
) {
  return sellerProfiles.values
      .map(SellerProfile.fromSupabase)
      .where((s) => s.isVerified)
      .toList();
}
