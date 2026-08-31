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

    final shopFields = <String, dynamic>{
      'shop_name': address.storeName.trim(),
      'shop_address': address.composedShopAddress,
      'barangay': address.barangay!.name,
      'city': DavaoBarangay.cityName,
      'application_type': 'seller',
      'government_id_type': SellerIdType.unspecifiedStorageValue,
      'liveness_passed': true,
      'liveness_result': liveness,
    };

    try {
      final existing = await _supabase.client
          .from('user_verifications')
          .select('verification_id')
          .eq('user_id', userId)
          .eq('verification_status', 'pending')
          .maybeSingle();

      final String verificationId;
      if (existing != null) {
        verificationId = existing['verification_id'] as String;
        await _supabase.client
            .from('user_verifications')
            .update(shopFields)
            .eq('verification_id', verificationId);
      } else {
        final inserted = await _supabase.client
            .from('user_verifications')
            .insert({
              ...shopFields,
              'user_id': userId,
              'verification_status': 'pending',
              'submitted_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select('verification_id')
            .single();
        verificationId = inserted['verification_id'] as String;
      }

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
    } catch (error) {
      debugPrint('SellerVerificationService.submitApplication: ${_describe(error)}');
      throw SellerSubmitException(sellerSubmitUserMessage(error), error);
    }
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

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return 'postgrest ${error.code} ${error.message}';
    }
    if (error is StorageException) {
      return 'storage ${error.statusCode} ${error.message}';
    }
    return error.toString();
  }
}

class SellerSubmitException implements Exception {
  SellerSubmitException(this.userMessage, [this.cause]);

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

String sellerSubmitUserMessage(Object error) {
  if (error is SellerSubmitException) return error.userMessage;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    if (code == '23505' || message.contains('one_pending')) {
      return 'You already have an application under review.';
    }
    if (code == '23502' || message.contains('not-null') || message.contains('null value')) {
      return 'The application is missing a required field. Please try again.';
    }
    if (code == '42501' || message.contains('row-level security')) {
      return 'Could not save the application. Please sign in again and retry.';
    }
  }
  if (error is StorageException) {
    return 'Could not upload your documents. Check your connection and try again.';
  }
  return 'Could not submit the application. Check your connection and try again.';
}
