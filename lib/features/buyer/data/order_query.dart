import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_errors.dart';
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
    'delivery_failure_reason, delivery_failure_details, auto_completed, '
    'completion_reason, completed_at, '
    'created_at, updated_at';

const String kReturnShipmentSelect =
    'return_id, dispute_id, order_id, buyer_id, seller_id, return_required, '
    'seller_pays_return, status, rider_name, rider_phone, vehicle_type, '
    'plate_number, return_notes, pickup_scheduled_at, picked_up_at, returned_at';

const String kOrderSelectWithoutShipment =
    '*, items:order_items(*), payments(payment_status, paymongo_channel), '
    'item_return:return_shipments($kReturnShipmentSelect)';

const String kOrderSelect =
    '*, items:order_items(*), payments(payment_status, paymongo_channel), '
    'shipment:shipments($kShipmentSelect), '
    'item_return:return_shipments($kReturnShipmentSelect)';

const String kAdminOrderDetailSelect =
    '*, items:order_items(*), payments(*)';

const String kAdminOrderDetailSelectWithShipment =
    '*, items:order_items(*), payments(*), '
    'shipment:shipments($kShipmentSelect), '
    'item_return:return_shipments($kReturnShipmentSelect)';

/// Runs an orders select with shipment embed; retries without shipments when
/// shipment privileges block the nested read (checkout must still load).
Future<T> runOrderSelect<T>(Future<T> Function(String select) run) async {
  try {
    return await run(kOrderSelect);
  } on PostgrestException catch (e) {
    if (!orderSelectMightNeedShipmentFallback(e)) rethrow;
    debugPrint(
      'order select with shipments failed ($e); retrying without shipment embed',
    );
    return await run(kOrderSelectWithoutShipment);
  }
}

/// Admin order detail — full payments; retries without shipment embed on RLS errors.
Future<T> runAdminOrderDetailSelect<T>(
  Future<T> Function(String select) run,
) async {
  try {
    return await run(kAdminOrderDetailSelectWithShipment);
  } on PostgrestException catch (e) {
    if (!orderSelectMightNeedShipmentFallback(e)) rethrow;
    debugPrint(
      'admin order detail with shipments failed ($e); retrying without shipment embed',
    );
    return await run(kAdminOrderDetailSelect);
  }
}

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

Future<void> syncMyUnpaidCheckouts(SupabaseService supabase) async {
  try {
    await supabase.client.rpc('sync_my_unpaid_checkouts');
  } catch (e) {
    debugPrint('sync_my_unpaid_checkouts error: $e');
  }
}

/// Restores abandoned fixed-price checkouts to the cart.
/// Do not call this on the payment screen — it would cancel the open checkout.
Future<void> restoreAbandonedFixedPriceCheckouts(
  SupabaseService supabase,
) async {
  try {
    await supabase.client.rpc('restore_my_unpaid_fixed_price_checkouts');
  } catch (e) {
    debugPrint('restore_my_unpaid_fixed_price_checkouts error: $e');
  }
}

List<OrderModel> buyerAwaitingPayment(Iterable<OrderModel> orders) {
  return orders.where((order) => order.showsAsAwaitingPayment).toList();
}

Future<List<OrderModel>> fetchOrdersForCheckoutGroup(
  SupabaseService supabase,
  String checkoutGroupId, {
  String? buyerId,
}) async {
  final rows = await runOrderSelect((select) {
    var q = supabase.client
        .from('orders')
        .select(select)
        .eq('checkout_group_id', checkoutGroupId);
    if (buyerId != null && buyerId.isNotEmpty) {
      q = q.eq('buyer_id', buyerId);
    }
    return q.order('created_at', ascending: true);
  });
  return hydrateOrders(
    supabase,
    (rows as List<dynamic>).map((r) => r as Map<String, dynamic>).toList(),
  );
}

Future<List<OrderModel>> fetchOrdersForBuyer(
  SupabaseService supabase,
  String buyerId,
) async {
  final rows = await runOrderSelect(
    (select) => supabase.client
        .from('orders')
        .select(select)
        .eq('buyer_id', buyerId)
        .order('created_at', ascending: false),
  );
  return hydrateOrders(
    supabase,
    (rows as List<dynamic>).map((r) => r as Map<String, dynamic>).toList(),
  );
}

Future<List<OrderModel>> fetchOrdersForSeller(
  SupabaseService supabase,
  String sellerId,
) async {
  final rows = await runOrderSelect(
    (select) => supabase.client
        .from('orders')
        .select(select)
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false),
  );
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
  final row = await runOrderSelect((select) {
    var query = supabase.client
        .from('orders')
        .select(select)
        .eq('order_id', orderId);
    // Keep the role-specific boundary in the query as well as in RLS. This
    // prevents a buyer who guesses another order id from receiving a seller's
    // participant-visible shipment row (including rider contact data).
    if (buyerId != null && buyerId.isNotEmpty) {
      query = query.eq('buyer_id', buyerId);
    } else if (sellerId != null && sellerId.isNotEmpty) {
      query = query.eq('seller_id', sellerId);
    }
    return query.maybeSingle();
  });
  if (row == null) return null;
  final list = await hydrateOrders(supabase, [row]);
  return list.isEmpty ? null : list.first;
}

Future<OrderModel?> fetchOrderByAuctionId(
  SupabaseService supabase,
  String auctionId,
) async {
  final row = await runOrderSelect(
    (select) => supabase.client
        .from('orders')
        .select(select)
        .eq('auction_id', auctionId)
        .maybeSingle(),
  );
  if (row == null) return null;
  final list = await hydrateOrders(supabase, [row]);
  return list.isEmpty ? null : list.first;
}
