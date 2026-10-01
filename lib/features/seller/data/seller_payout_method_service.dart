import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ph_phone.dart';
import 'seller_payout_method.dart';

bool isLikelyOfflineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('host lookup') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('offline') ||
      text.contains('timed out');
}

class SellerPayoutMethodService {
  SellerPayoutMethodService(this._supabase);

  final SupabaseService _supabase;

  Future<SellerPayoutMethod?> loadMine() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await _supabase.client
          .from('seller_payout_methods')
          .select('account_name, mobile_number, method')
          .eq('seller_id', userId)
          .maybeSingle();
      if (row == null) {
        await _clearCache(userId);
        return null;
      }
      final method = SellerPayoutMethod.fromMap(Map<String, dynamic>.from(row));
      await _writeCache(userId, method);
      return method;
    } catch (e) {
      debugPrint('SellerPayoutMethodService.loadMine: $e');
      rethrow;
    }
  }

  Future<SellerPayoutMethod?> readCache() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey(userId));
    final mobile = prefs.getString(_mobileKey(userId));
    if (name == null || mobile == null) return null;
    final method = SellerPayoutMethod(accountName: name, mobileNumber: mobile);
    return method.isComplete ? method : null;
  }

  Future<String?> save({
    required String accountName,
    required String mobileNumber,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return 'Please sign in.';
    final nameError = gcashAccountNameError(accountName);
    if (nameError != null) return nameError;
    final mobileError = gcashMobileError(mobileNumber);
    if (mobileError != null) return mobileError;
    final mobile = normalizePhMobile(mobileNumber);
    if (mobile == null) {
      return 'Enter a GCash number in 09XXXXXXXXX format.';
    }

    try {
      await _supabase.client.from('seller_payout_methods').upsert({
        'seller_id': userId,
        'method': 'gcash',
        'account_name': accountName.trim(),
        'mobile_number': mobile,
      });
      await _writeCache(
        userId,
        SellerPayoutMethod(
          accountName: accountName.trim(),
          mobileNumber: mobile,
        ),
      );
      return null;
    } catch (e) {
      debugPrint('SellerPayoutMethodService.save: $e');
      if (isLikelyOfflineError(e)) {
        return 'No internet connection. Check your connection and try again.';
      }
      return 'Could not save your GCash details.';
    }
  }

  Future<String?> deleteMine() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return 'Please sign in.';
    try {
      await _supabase.client
          .from('seller_payout_methods')
          .delete()
          .eq('seller_id', userId);
      await _clearCache(userId);
      return null;
    } catch (e) {
      debugPrint('SellerPayoutMethodService.deleteMine: $e');
      if (isLikelyOfflineError(e)) {
        return 'No internet connection. Check your connection and try again.';
      }
      return 'Could not remove your GCash details.';
    }
  }

  String _nameKey(String userId) => 'seller_gcash_name_$userId';
  String _mobileKey(String userId) => 'seller_gcash_mobile_$userId';

  Future<void> _writeCache(String userId, SellerPayoutMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey(userId), method.accountName);
    await prefs.setString(_mobileKey(userId), method.mobileNumber);
  }

  Future<void> _clearCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey(userId));
    await prefs.remove(_mobileKey(userId));
  }
}
