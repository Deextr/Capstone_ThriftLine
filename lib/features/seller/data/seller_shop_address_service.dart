import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/davao_barangay.dart';
import '../domain/seller_address_draft.dart';
import 'seller_shop_address.dart';

class SellerShopAddressService {
  SellerShopAddressService(this._supabase);

  final SupabaseService _supabase;

  Future<SellerShopAddress?> loadMine() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return null;

    try {
      final row = await _supabase.client
          .from('seller_profiles')
          .select('shop_name, shop_address, barangay, city')
          .eq('seller_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return SellerShopAddress.fromProfileRow(
        Map<String, dynamic>.from(row as Map),
      );
    } catch (e) {
      debugPrint('SellerShopAddressService.loadMine: $e');
      rethrow;
    }
  }

  Future<String?> updateMine({required SellerAddressDraft draft}) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return 'Please sign in.';

    if (draft.barangay == null || !draft.barangay!.isDavaoCity) {
      return 'Please select a Davao City barangay.';
    }

    final shopName = draft.storeName.trim();
    if (shopName.length < 2) {
      return 'Shop name must be at least 2 characters.';
    }

    try {
      await _supabase.client
          .from('seller_profiles')
          .update({
            'shop_name': shopName,
            'shop_address': draft.composedShopAddress,
            'barangay': draft.barangay!.name,
            'city': DavaoBarangay.cityName,
          })
          .eq('seller_id', userId);
      return null;
    } catch (e) {
      debugPrint('SellerShopAddressService.updateMine: $e');
      return 'Could not save your shop address. Please try again.';
    }
  }
}
