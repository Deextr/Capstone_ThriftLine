import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/davao_barangay.dart';
import '../domain/seller_address_draft.dart';
import '../domain/seller_id_type.dart';

class SellerVerificationService {
  SellerVerificationService(this._supabase);

  final SupabaseService _supabase;

  Future<void> submitApplication({
    required SellerAddressDraft address,
    required SellerIdType idType,
    required Uint8List idFrontBytes,
    required Uint8List idBackBytes,
    required Uint8List selfieBytes,
    required String selfieFileName,
    required Map<String, bool> liveness,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      throw StateError('You must be signed in to apply.');
    }
    if (!address.barangay!.isDavaoCity) {
      throw StateError('Shop address must be in Davao City.');
    }

    final inserted = await _supabase.client
        .from('user_verifications')
        .insert({
          'user_id': userId,
          'shop_name': address.storeName.trim(),
          'shop_address': address.composedShopAddress,
          'barangay': address.barangay!.name,
          'city': DavaoBarangay.cityName,
          'application_type': 'seller',
          'verification_status': 'pending',
          'government_id_type': idType.storageValue,
          'liveness_passed': true,
          'liveness_result': liveness,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('verification_id')
        .single();

    final verificationId = inserted['verification_id'] as String;
    final frontPath = '$userId/$verificationId/id_front.jpg';
    final backPath = '$userId/$verificationId/id_back.jpg';
    final selfiePath = '$userId/$verificationId/selfie${_ext(selfieFileName)}';

    await _supabase.client.storage.from('verification-docs').uploadBinary(
          frontPath,
          idFrontBytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    await _supabase.client.storage.from('verification-docs').uploadBinary(
          backPath,
          idBackBytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    await _supabase.client.storage.from('verification-docs').uploadBinary(
          selfiePath,
          selfieBytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentType(selfieFileName),
          ),
        );

    await _supabase.client.from('user_verifications').update({
      'government_id_front': frontPath,
      'government_id_back': backPath,
      'selfie_image': selfiePath,
    }).eq('verification_id', verificationId);
  }

  String _ext(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
