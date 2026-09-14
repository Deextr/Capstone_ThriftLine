import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/order_model.dart';

const String kShipmentSelect =
    'shipment_id, order_id, delivery_method, rider_name, rider_phone, '
    'vehicle_type, plate_number, delivery_notes, delivery_status, '
    'estimated_delivery_at, rider_assigned_at, ready_for_pickup_at, '
    'picked_up_at, out_for_delivery_at, delivery_pin_expires_at, '
    'delivery_pin_attempts, delivery_pin_locked_until, delivery_pin_used_at, '
    'delivery_verified_at, delivery_verification_method, '
    'buyer_confirmed_received, buyer_confirmed_received_at, '
    'inspection_started_at, inspection_expires_at, delivery_failed_at, '
    'delivery_failure_reason, auto_completed, completion_reason, completed_at, '
    'created_at, updated_at';

const String kOrderSelect =
    '*, items:order_items(*), payments(payment_status, paymongo_channel), '
    'shipment:shipments($kShipmentSelect)';

Future<Map<String, Map<String, dynamic>>> loadPublicProfiles(
  SupabaseService supabase,
  Iterable<String> ids,
) async {
  final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return {};
  final out = <String, Map<String, dynamic>>{};
  try {
    final rows = await supabase.client
        .from('user_public_profiles')
        .select()
        .inFilter('user_id', unique);
    for (final raw in rows as List<dynamic>) {
      final map = raw as Map<String, dynamic>;
      final id = map['user_id'] as String?;
      if (id != null) out[id] = map;
    }
  } catch (e) {
    debugPrint('loadPublicProfiles error ($e)');
  }
  try {
    final shopRows = await supabase.client
        .from('seller_profiles')
        .select('seller_id, shop_name')
        .inFilter('seller_id', unique);
    for (final raw in shopRows as List<dynamic>) {
      final map = raw as Map<String, dynamic>;
      final id = map['seller_id'] as String?;
      if (id == null) continue;
      final current = Map<String, dynamic>.from(out[id] ?? {});
      current['shop_name'] = map['shop_name'];
      out[id] = current;
    }
  } catch (e) {
    debugPrint('loadPublicProfiles shops error ($e)');
  }
  return out;
}

Future<List<OrderModel>> hydrateOrders(
  SupabaseService supabase,
  List<Map<String, dynamic>> rows,
) async {
  final ids = <String>{};
  for (final row in rows) {
    final buyer = row['buyer_id'] as String?;
    final seller = row['seller_id'] as String?;
    if (buyer != null) ids.add(buyer);
    if (seller != null) ids.add(seller);
  }
  final profiles = await loadPublicProfiles(supabase, ids);
  return rows
      .map(
        (row) => OrderModel.fromSupabase(
          row,
          buyer: profiles[row['buyer_id'] as String?],
          seller: profiles[row['seller_id'] as String?],
        ),
      )
      .toList();
}

Future<List<OrderModel>> fetchOrdersForBuyer(
  SupabaseService supabase,
  String buyerId,
) async {
  final rows = await supabase.client
      .from('orders')
      .select(kOrderSelect)
      .eq('buyer_id', buyerId)
      .order('created_at', ascending: false);
  return hydrateOrders(
    supabase,
    (rows as List<dynamic>).map((r) => r as Map<String, dynamic>).toList(),
  );
}

Future<List<OrderModel>> fetchOrdersForSeller(
  SupabaseService supabase,
  String sellerId,
) async {
  final rows = await supabase.client
      .from('orders')
      .select(kOrderSelect)
      .eq('seller_id', sellerId)
      .order('created_at', ascending: false);
  return hydrateOrders(
    supabase,
    (rows as List<dynamic>).map((r) => r as Map<String, dynamic>).toList(),
  );
}

Future<OrderModel?> fetchOrderById(
  SupabaseService supabase,
  String orderId, {
  String? buyerId,
  String? sellerId,
}) async {
  var query = supabase.client
      .from('orders')
      .select(kOrderSelect)
      .eq('order_id', orderId);
  // Keep the role-specific boundary in the query as well as in RLS. This
  // prevents a buyer who guesses another order id from receiving a seller's
  // participant-visible shipment row (including rider contact data).
  if (buyerId != null && buyerId.isNotEmpty) {
    query = query.eq('buyer_id', buyerId);
  } else if (sellerId != null && sellerId.isNotEmpty) {
    query = query.eq('seller_id', sellerId);
  }
  final row = await query.maybeSingle();
  if (row == null) return null;
  final list = await hydrateOrders(supabase, [row]);
  return list.isEmpty ? null : list.first;
}

Future<OrderModel?> fetchOrderByAuctionId(
  SupabaseService supabase,
  String auctionId,
) async {
  final row = await supabase.client
      .from('orders')
      .select(kOrderSelect)
      .eq('auction_id', auctionId)
      .maybeSingle();
  if (row == null) return null;
  final list = await hydrateOrders(supabase, [row]);
  return list.isEmpty ? null : list.first;
}
